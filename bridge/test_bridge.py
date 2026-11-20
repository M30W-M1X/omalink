#!/usr/bin/env python3
"""Unit and integration tests for Omarchy Wizard Bridge."""

from __future__ import annotations

import asyncio
import base64
import json
import os
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from urllib import error, request
from urllib.parse import quote

import omarchy_continuity
import omarchy_control
import omarchy_desktop
import omarchy_files
from omarchy_wizard_bridge import (
    OmarchyWizardBridge,
    build_agent_command,
    generate_pairing_token,
    load_or_create_token,
    parse_agent_output_line,
)


def _http_json(url: str, method: str = "GET", token: str | None = None, body: dict | None = None) -> tuple[int, dict]:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = request.Request(url, data=data, headers=headers, method=method)
    try:
        with request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except error.HTTPError as exc:
        with exc:
            return exc.code, json.loads(exc.read().decode("utf-8"))


async def _ws_read_frame(reader: asyncio.StreamReader) -> tuple[int, bytes]:
    b1, b2 = await reader.readexactly(2)
    opcode = b1 & 0x0F
    length = b2 & 0x7F
    if length == 126:
        length = struct.unpack("!H", await reader.readexactly(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", await reader.readexactly(8))[0]
    payload = await reader.readexactly(length)
    return opcode, payload


async def _ws_send_masked_text(writer: asyncio.StreamWriter, text: str) -> None:
    payload = text.encode("utf-8")
    mask = b"\x12\x34\x56\x78"
    header = bytearray([0x81])
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    writer.write(bytes(header) + mask + masked)
    await writer.drain()


class BridgeTests(unittest.TestCase):
    def test_command_builders(self) -> None:
        agy_cmd = build_agent_command("agy", "Fix bug", mode="plan", effort="high", conversation_id="abc")
        self.assertEqual(agy_cmd[:3], ["agy", "--output-format", "stream-json"])
        self.assertIn("--mode", agy_cmd)
        self.assertIn("plan", agy_cmd)
        self.assertIn("--conversation", agy_cmd)
        self.assertEqual(agy_cmd[-2:], ["-p", "Fix bug"])

        claude_cmd = build_agent_command("claude", "Hello", mode="accept-edits")
        self.assertIn("acceptEdits", claude_cmd)
        self.assertEqual(claude_cmd[-1], "Hello")

        kimi_cmd = build_agent_command("kimi", "Hello")
        self.assertEqual(kimi_cmd[-2:], ["-p", "Hello"])

    def test_parse_agent_output_line(self) -> None:
        ev = parse_agent_output_line(
            '{"type":"assistant","conversation_id":"c-123","message":"Casting spell"}'
        )
        self.assertEqual(ev["kind"], "assistant")
        self.assertEqual(ev["conversation_id"], "c-123")
        self.assertEqual(ev["text"], "Casting spell")

        agy_delta = parse_agent_output_line(
            '{"event":"step_update","step_update":{"conversation_id":"agy-1","step_type":"agent_response","text_delta":"Hello wizard"}}'
        )
        self.assertEqual(agy_delta["kind"], "step_update")
        self.assertEqual(agy_delta["conversation_id"], "agy-1")
        self.assertEqual(agy_delta["text"], "Hello wizard")

        agy_result = parse_agent_output_line(
            '{"event":"result","result":{"conversation_id":"agy-1","status":"SUCCESS","response":"Done casting"}}'
        )
        self.assertEqual(agy_result["kind"], "result")
        self.assertEqual(agy_result["conversation_id"], "agy-1")
        self.assertEqual(agy_result["text"], "Done casting")

        plain = parse_agent_output_line("plain log line", stream="stderr")
        self.assertEqual(plain["kind"], "stderr")
        self.assertEqual(plain["text"], "plain log line")

    def test_http_and_websocket_task_lifecycle(self) -> None:
        asyncio.run(self._run_lifecycle_test())

    async def _run_lifecycle_test(self) -> None:
        bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token="secret-wizard-token")
        await bridge.start()
        port = bridge.bound_port
        try:
            # Unauthorized rejected
            code, _ = await asyncio.to_thread(
                _http_json, f"http://127.0.0.1:{port}/api/status", "GET", "wrong-token"
            )
            self.assertEqual(code, 401)

            # Status works with token
            code, status_data = await asyncio.to_thread(
                _http_json, f"http://127.0.0.1:{port}/api/status", "GET", "secret-wizard-token"
            )
            self.assertEqual(code, 200)
            self.assertTrue(status_data["ok"])
            self.assertIn("default_agent", status_data)
            self.assertNotIn("pair_uri", status_data)

            # Connect WebSocket client via Authorization header
            ws_reader, ws_writer = await asyncio.open_connection("127.0.0.1", port)
            ws_key = base64.b64encode(os.urandom(16)).decode("ascii")
            handshake = (
                "GET /ws HTTP/1.1\r\n"
                f"Host: 127.0.0.1:{port}\r\n"
                "Authorization: Bearer secret-wizard-token\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Key: {ws_key}\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n"
            )
            ws_writer.write(handshake.encode("ascii"))
            await ws_writer.drain()
            raw_resp = await ws_reader.readuntil(b"\r\n\r\n")
            self.assertIn(b"101 Switching Protocols", raw_resp)

            _, hello_bytes = await _ws_read_frame(ws_reader)
            hello_msg = json.loads(hello_bytes.decode("utf-8"))
            self.assertEqual(hello_msg["type"], "hello")

            # Launch mock agent task
            code, created = await asyncio.to_thread(
                _http_json,
                f"http://127.0.0.1:{port}/api/tasks",
                "POST",
                "secret-wizard-token",
                {"prompt": "Summon tests", "agent": "mock"},
            )
            self.assertEqual(code, 201)
            task_id = created["task"]["id"]

            seen_types: list[str] = []
            for _ in range(10):
                _, frame_bytes = await asyncio.wait_for(_ws_read_frame(ws_reader), timeout=5.0)
                msg = json.loads(frame_bytes.decode("utf-8"))
                seen_types.append(msg["type"])
                if msg["type"] == "task.completed":
                    self.assertEqual(msg["data"]["id"], task_id)
                    self.assertIn("Spell completed for: Summon tests", msg["data"]["summary"])
                    break

            self.assertIn("task.started", seen_types)
            self.assertIn("task.event", seen_types)
            self.assertIn("task.completed", seen_types)

            # Test task cancellation via HTTP
            sleep_task = await bridge.start_task(prompt="Long spell", agent="mock")
            code, cancel_resp = await asyncio.to_thread(
                _http_json,
                f"http://127.0.0.1:{port}/api/tasks/{sleep_task.id}/cancel",
                "POST",
                "secret-wizard-token",
                {},
            )
            self.assertEqual(code, 200)
            self.assertEqual(cancel_resp["task"]["status"], "cancelled")

            ws_writer.close()
            await ws_writer.wait_closed()
        finally:
            await bridge.stop()

    def test_generated_token_is_strong_and_rotates_legacy_weak_tokens(self) -> None:
        token = generate_pairing_token()
        self.assertGreaterEqual(len(token), 32)
        self.assertFalse(token.isdigit())

        with tempfile.TemporaryDirectory() as tmpdir:
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": tmpdir}, clear=False):
                os.environ.pop("OMARCHY_WIZARD_TOKEN", None)
                os.environ.pop("OMALINK_TOKEN", None)
                created = load_or_create_token()
                self.assertGreaterEqual(len(created), 32)
                self.assertFalse(created.isdigit())
                token_path = Path(tmpdir) / "omalink" / "token"
                self.assertEqual(token_path.read_text(encoding="utf-8").strip(), created)
                self.assertEqual(os.stat(token_path).st_mode & 0o777, 0o600)
                self.assertEqual(load_or_create_token(), created)

                # A legacy weak 5-digit PIN must be auto-rotated to a strong token
                token_path.write_text("12345\n", encoding="utf-8")
                rotated = load_or_create_token()
                self.assertNotEqual(rotated, "12345")
                self.assertGreaterEqual(len(rotated), 32)

    def test_system_state_and_action_endpoints(self) -> None:
        asyncio.run(self._run_control_and_files_test())

    async def _run_control_and_files_test(self) -> None:
        bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token="12345")
        await bridge.start()
        port = bridge.bound_port
        try:
            with mock.patch.object(
                omarchy_control,
                "read_system_state_sync",
                return_value={
                    "hostname": "kitsune",
                    "os_version": "4.5.0-3",
                    "uptime_seconds": 120,
                    "cpu_percent": 12.0,
                    "load_avg": "0.42",
                    "memory": {"used_gb": 8.0, "total_gb": 32.0, "percent": 25.0},
                    "battery": {"present": False, "percent": 0, "status": "none"},
                    "audio": {"volume": 40, "muted": False, "mic_muted": False, "default_sink": "usb", "sinks": [], "player": {"available": False, "status": "Stopped", "title": "", "artist": ""}},
                    "brightness": {"available": False, "percent": 0},
                    "hyprland": {"workspaces": [], "active_window": {"title": "", "class": "", "address": ""}},
                    "toggles": {"nightlight": False, "stay_awake": False, "bar_hidden": False, "screensaver_off": False, "animations_off": False},
                    "theme": {"current": "Everforest", "themes": ["Everforest", "Catppuccin"]},
                    "security": {"passwordless_sudo": False, "bluetooth_powered": True, "tailscale_active": False},
                },
            ):
                code, state = await asyncio.to_thread(
                    _http_json, f"http://127.0.0.1:{port}/api/system/state", "GET", "12345"
                )
                self.assertEqual(code, 200)
                self.assertEqual(state["hostname"], "kitsune")
                self.assertEqual(state["theme"]["current"], "Everforest")

            # Unknown actions must fail cleanly with 400
            code, err = await asyncio.to_thread(
                _http_json,
                f"http://127.0.0.1:{port}/api/system/action",
                "POST",
                "12345",
                {"action": "rm.rf.everything"},
            )
            self.assertEqual(code, 400)
            self.assertFalse(err["ok"])

            # Remote file explorer roundtrip in isolated temp directory
            with tempfile.TemporaryDirectory() as tmpdir:
                sample = Path(tmpdir) / "notes.txt"
                sample.write_text("arcane runes\nline 2\n", encoding="utf-8")

                code, listing = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/files/list?path={quote(tmpdir)}",
                    "GET",
                    "12345",
                )
                self.assertEqual(code, 200)
                self.assertEqual(len(listing["entries"]), 1)
                self.assertEqual(listing["entries"][0]["name"], "notes.txt")

                code, preview = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/files/read?path={quote(str(sample))}",
                    "GET",
                    "12345",
                )
                self.assertEqual(code, 200)
                self.assertFalse(preview["is_binary"])
                self.assertIn("arcane runes", preview["content"])

                code, mk = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/files/mkdir",
                    "POST",
                    "12345",
                    {"parent": tmpdir, "name": "spells"},
                )
                self.assertEqual(code, 201)
                self.assertTrue(mk["entry"]["is_dir"])

                code, ren = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/files/rename",
                    "POST",
                    "12345",
                    {"path": str(sample), "new_name": "scroll.txt"},
                )
                self.assertEqual(code, 200)
                self.assertEqual(ren["entry"]["name"], "scroll.txt")
        finally:
            await bridge.stop()

    def test_mpris_media_discovery_and_selection(self) -> None:
        buses = [
            "org.mpris.MediaPlayer2.firefox.instance_1_2",
            "org.mpris.MediaPlayer2.spotify",
        ]

        def fake_prop(bus: str, iface: str, prop: str):
            data = {
                ("org.mpris.MediaPlayer2.firefox.instance_1_2", "Identity"): "Firefox",
                ("org.mpris.MediaPlayer2.firefox.instance_1_2", "PlaybackStatus"): "Paused",
                ("org.mpris.MediaPlayer2.firefox.instance_1_2", "Metadata"): {
                    "xesam:title": {"type": "s", "data": "Lo-Fi Stream"},
                    "xesam:artist": {"type": "as", "data": ["Stream"]},
                },
                ("org.mpris.MediaPlayer2.spotify", "Identity"): "Spotify",
                ("org.mpris.MediaPlayer2.spotify", "PlaybackStatus"): "Playing",
                ("org.mpris.MediaPlayer2.spotify", "Metadata"): {
                    "xesam:title": {"type": "s", "data": "Arcane Waves"},
                    "xesam:artist": {"type": "as", "data": ["Wizard"]},
                    "xesam:album": {"type": "s", "data": "Omarchy"},
                },
                ("org.mpris.MediaPlayer2.spotify", "Shuffle"): True,
                ("org.mpris.MediaPlayer2.spotify", "LoopStatus"): "Playlist",
            }
            return data.get((bus, prop))

        omarchy_control._SELECTED_MEDIA_BUS = ""
        with mock.patch.object(omarchy_control, "_list_mpris_buses", return_value=buses):
            with mock.patch.object(omarchy_control, "_busctl_get_prop", side_effect=fake_prop):
                primary, players = omarchy_control._read_media_players()
                self.assertEqual(len(players), 2)
                # Active Playing player (Spotify) should be preferred over Paused Firefox
                self.assertEqual(primary["identity"], "Spotify")
                self.assertEqual(primary["title"], "Arcane Waves")
                self.assertTrue(primary["shuffle"])

                ok, msg = omarchy_control._dispatch_media_action(
                    "media.select_player",
                    {"bus_name": "org.mpris.MediaPlayer2.firefox.instance_1_2"},
                )
                self.assertTrue(ok)
                self.assertIn("Firefox", msg)
                primary2, _ = omarchy_control._read_media_players()
                self.assertEqual(primary2["identity"], "Firefox")

    def test_terminal_websocket_pty_roundtrip(self) -> None:
        asyncio.run(self._run_terminal_pty_test())

    async def _run_terminal_pty_test(self) -> None:
        bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token="term-token")
        await bridge.start()
        port = bridge.bound_port
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                # Reject unauthorized terminal connection
                r_bad, w_bad = await asyncio.open_connection("127.0.0.1", port)
                key = base64.b64encode(os.urandom(16)).decode("ascii")
                bad_req = (
                    "GET /ws/terminal?token=wrong HTTP/1.1\r\n"
                    f"Host: 127.0.0.1:{port}\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Key: {key}\r\n"
                    "Sec-WebSocket-Version: 13\r\n\r\n"
                )
                w_bad.write(bad_req.encode("ascii"))
                await w_bad.drain()
                status_line = (await r_bad.readline()).decode("ascii")
                self.assertIn("401", status_line)
                w_bad.close()
                await w_bad.wait_closed()

                # Connect authenticated terminal WebSocket via Authorization header
                ws_reader, ws_writer = await asyncio.open_connection("127.0.0.1", port)
                ws_key = base64.b64encode(os.urandom(16)).decode("ascii")
                req = (
                    f"GET /ws/terminal?cols=100&rows=30&cwd={quote(tmpdir)} HTTP/1.1\r\n"
                    f"Host: 127.0.0.1:{port}\r\n"
                    "Authorization: Bearer term-token\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Key: {ws_key}\r\n"
                    "Sec-WebSocket-Version: 13\r\n\r\n"
                )
                ws_writer.write(req.encode("ascii"))
                await ws_writer.drain()
                handshake = await ws_reader.readuntil(b"\r\n\r\n")
                self.assertIn(b"101 Switching Protocols", handshake)

                _, ready_raw = await asyncio.wait_for(_ws_read_frame(ws_reader), timeout=5.0)
                ready = json.loads(ready_raw.decode("utf-8"))
                self.assertEqual(ready["type"], "ready")
                self.assertEqual(ready["cols"], 100)
                self.assertEqual(ready["rows"], 30)
                self.assertEqual(ready["cwd"], str(Path(tmpdir).resolve()))

                await _ws_send_masked_text(
                    ws_writer, json.dumps({"type": "resize", "cols": 120, "rows": 40})
                )
                await _ws_send_masked_text(
                    ws_writer,
                    json.dumps({"type": "input", "data": "pwd && echo PTY_OK_42 && exit\n"}),
                )

                output_chunks: list[str] = []
                exit_code = None
                for _ in range(80):
                    opcode, raw = await asyncio.wait_for(_ws_read_frame(ws_reader), timeout=5.0)
                    if opcode == 0x8:
                        break
                    if opcode != 0x1:
                        continue
                    msg = json.loads(raw.decode("utf-8"))
                    if msg.get("type") == "output":
                        output_chunks.append(msg["data"])
                    elif msg.get("type") == "exit":
                        exit_code = msg.get("code")
                        break

                combined = "".join(output_chunks)
                self.assertIn("PTY_OK_42", combined)
                self.assertIn(str(Path(tmpdir).resolve()), combined)
                self.assertEqual(exit_code, 0)

                ws_writer.close()
                await ws_writer.wait_closed()
        finally:
            await bridge.stop()

    def test_desktop_coordinate_mapping_and_ws_stream(self) -> None:
        monitors = [
            {"name": "DP-1", "width": 5120, "height": 1440, "x": 0, "y": 0, "focused": True},
            {"name": "HDMI-A-1", "width": 1920, "height": 1080, "x": 5120, "y": 0, "focused": False},
        ]
        ax, ay, ew, eh = omarchy_desktop.map_normalized_point(0.5, 0.5, monitors, "DP-1")
        self.assertEqual((ew, eh), (7040, 1440))
        self.assertAlmostEqual(ax, 2560, delta=1)
        self.assertAlmostEqual(ay, 720, delta=1)

        bx, by, _, _ = omarchy_desktop.map_normalized_point(0.0, 1.0, monitors, "HDMI-A-1")
        self.assertEqual(bx, 5120)
        self.assertAlmostEqual(by, 1079, delta=1)

        asyncio.run(self._run_desktop_ws_test())

    async def _run_desktop_ws_test(self) -> None:
        bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token="desk-token")
        await bridge.start()
        port = bridge.bound_port
        fake_jpeg = b"\xff\xd8\xff\xe0FAKEJPEG"
        try:
            with (
                mock.patch.object(
                    omarchy_desktop,
                    "read_monitors_and_workspaces_sync",
                    return_value={
                        "monitors": [{"name": "DP-1", "width": 5120, "height": 1440, "x": 0, "y": 0, "focused": True}],
                        "workspaces": [{"id": 1, "name": "1", "windows": 2}],
                    },
                ),
                mock.patch.object(
                    omarchy_desktop.WaylandVirtualPointer,
                    "connect",
                    return_value=False,
                ),
                mock.patch.object(
                    omarchy_desktop,
                    "capture_frame_jpeg",
                    new=mock.AsyncMock(return_value=fake_jpeg),
                ),
            ):
                ws_reader, ws_writer = await asyncio.open_connection("127.0.0.1", port)
                ws_key = base64.b64encode(os.urandom(16)).decode("ascii")
                req = (
                    f"GET /ws/desktop?scale=0.35&quality=60&fps=4 HTTP/1.1\r\n"
                    f"Host: 127.0.0.1:{port}\r\n"
                    "Authorization: Bearer desk-token\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Key: {ws_key}\r\n"
                    "Sec-WebSocket-Version: 13\r\n\r\n"
                )
                ws_writer.write(req.encode("ascii"))
                await ws_writer.drain()
                handshake = await ws_reader.readuntil(b"\r\n\r\n")
                self.assertIn(b"101 Switching Protocols", handshake)

                op1, ready_raw = await asyncio.wait_for(_ws_read_frame(ws_reader), timeout=5.0)
                self.assertEqual(op1, 0x1)
                ready = json.loads(ready_raw.decode("utf-8"))
                self.assertEqual(ready["type"], "ready")
                self.assertEqual(ready["monitor"]["name"], "DP-1")

                op2, bin_frame = await asyncio.wait_for(_ws_read_frame(ws_reader), timeout=5.0)
                self.assertEqual(op2, 0x2)
                self.assertEqual(bin_frame, fake_jpeg)

                await _ws_send_masked_text(ws_writer, json.dumps({"type": "ping"}))
                op3, pong_raw = await asyncio.wait_for(_ws_read_frame(ws_reader), timeout=5.0)
                self.assertEqual(op3, 0x1)
                self.assertEqual(json.loads(pong_raw.decode("utf-8"))["type"], "pong")

                ws_writer.close()
                await ws_writer.wait_closed()
        finally:
            await bridge.stop()

    def test_continuity_notify_clipboard_and_handoff(self) -> None:
        self.assertEqual(
            omarchy_continuity.extract_first_url("Check this article https://archlinux.org/packages/!"),
            "https://archlinux.org/packages/",
        )
        self.assertEqual(
            omarchy_continuity.resolve_app_key(package_name="com.android.chrome"),
            "browser",
        )
        self.assertEqual(
            omarchy_continuity.resolve_app_key(package_name="com.spotify.music"),
            "spotify",
        )
        asyncio.run(self._run_continuity_http_test())

    async def _run_continuity_http_test(self) -> None:
        bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token="cont-token")
        await bridge.start()
        port = bridge.bound_port
        try:
            with (
                mock.patch.object(omarchy_continuity.shutil, "which", return_value="/usr/bin/true"),
                mock.patch.object(omarchy_continuity, "_spawn_detached", return_value=True) as mock_spawn,
                mock.patch.object(
                    omarchy_continuity,
                    "set_clipboard_sync",
                    return_value={"ok": True, "length": 11, "preview": "hello world", "message": "ok"},
                ),
                mock.patch.object(
                    omarchy_continuity,
                    "get_clipboard_sync",
                    return_value={"ok": True, "text": "from-desktop", "empty": False},
                ),
            ):
                # Phone notification / incoming call relay
                code, notif_resp = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/continuity/notify",
                    "POST",
                    "cont-token",
                    {
                        "title": "Alice",
                        "body": "Hey, are you free?",
                        "app_name": "Messages",
                        "category": "message",
                    },
                )
                self.assertEqual(code, 200)
                self.assertTrue(notif_resp["ok"])
                self.assertEqual(notif_resp["entry"]["category"], "message")

                code, call_resp = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/continuity/notify",
                    "POST",
                    "cont-token",
                    {"caller": "Mom", "category": "call"},
                )
                self.assertEqual(code, 200)
                self.assertEqual(call_resp["entry"]["urgency"], "critical")
                self.assertIn("Incoming Call: Mom", call_resp["entry"]["title"])

                # Clipboard set & get
                code, clip_set = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/continuity/clipboard",
                    "POST",
                    "cont-token",
                    {"text": "hello world"},
                )
                self.assertEqual(code, 200)
                self.assertEqual(clip_set["preview"], "hello world")

                code, clip_get = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/continuity/clipboard",
                    "GET",
                    "cont-token",
                )
                self.assertEqual(code, 200)
                self.assertEqual(clip_get["text"], "from-desktop")

                # Continue from Chrome URL
                code, handoff_resp = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/continuity/handoff",
                    "POST",
                    "cont-token",
                    {
                        "text": "Cool doc https://wiki.archlinux.org",
                        "subject": "Arch Wiki",
                        "package_name": "com.android.chrome",
                    },
                )
                self.assertEqual(code, 200)
                self.assertTrue(handoff_resp["ok"])
                self.assertEqual(handoff_resp["url"], "https://wiki.archlinux.org")
                self.assertTrue(mock_spawn.called)
        finally:
            await bridge.stop()

    def test_theme_palette_parsing_and_endpoint(self) -> None:
        self.assertEqual(omarchy_control.theme_slug_from_name("Catppuccin Latte"), "catppuccin-latte")
        self.assertEqual(omarchy_control.theme_display_name("catppuccin-latte"), "Catppuccin Latte")

        with tempfile.TemporaryDirectory() as tmpdir:
            theme_dir = Path(tmpdir) / ".local" / "state" / "omarchy" / "current" / "theme"
            theme_dir.mkdir(parents=True)
            (theme_dir.parent / "theme.name").write_text("catppuccin-latte\n", encoding="utf-8")
            (theme_dir.parent / "theme.generation").write_text("gen-42\n", encoding="utf-8")
            (theme_dir / "colors.toml").write_text(
                'mode = "light"\naccent = "#1e66f5"\nbackground = "#eff1f5"\nforeground = "#4c4f69"\n',
                encoding="utf-8",
            )
            with mock.patch.object(omarchy_control.Path, "home", return_value=Path(tmpdir)):
                palette = omarchy_control.read_theme_palette_sync()
                self.assertEqual(palette["slug"], "catppuccin-latte")
                self.assertEqual(palette["name"], "Catppuccin Latte")
                self.assertEqual(palette["mode"], "light")
                self.assertEqual(palette["generation"], "gen-42")
                self.assertEqual(palette["colors"]["accent"], "#1e66f5")
                self.assertEqual(palette["colors"]["background"], "#eff1f5")

                asyncio.run(self._run_theme_endpoint_test(palette))

    async def _run_theme_endpoint_test(self, expected: dict) -> None:
        bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token="theme-tok")
        await bridge.start()
        port = bridge.bound_port
        try:
            code, resp = await asyncio.to_thread(
                _http_json,
                f"http://127.0.0.1:{port}/api/theme/current",
                "GET",
                "theme-tok",
            )
            self.assertEqual(code, 200)
            self.assertEqual(resp["slug"], expected["slug"])
            self.assertEqual(resp["colors"]["accent"], "#1e66f5")
        finally:
            await bridge.stop()

    def test_v2_file_transfer_reply_ring_pairing_and_usage(self) -> None:
        asyncio.run(self._run_v2_endpoints_test())

    async def _run_v2_endpoints_test(self) -> None:
        bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token="v2-tok")
        await bridge.start()
        port = bridge.bound_port
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                # 1. File upload & download roundtrip
                raw = b"Hello Omarchy AirDrop 2.0!"
                code, up = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/files/upload",
                    "POST",
                    "v2-tok",
                    {
                        "filename": "note.bin",
                        "data_base64": base64.b64encode(raw).decode("ascii"),
                        "dir": tmpdir,
                    },
                )
                self.assertEqual(code, 201)
                self.assertTrue(up["ok"])
                uploaded_path = up["path"]
                self.assertTrue(Path(uploaded_path).is_file())

                def _download(url: str) -> bytes:
                    req = request.Request(url, headers={"Authorization": "Bearer v2-tok"})
                    with request.urlopen(req, timeout=5) as r:
                        return r.read()

                dl = await asyncio.to_thread(
                    _download,
                    f"http://127.0.0.1:{port}/api/files/download?path={quote(uploaded_path)}",
                )
                self.assertEqual(dl, raw)

                # 2. Phone battery telemetry + Find My Phone ring + inline reply
                code, dev = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/continuity/device",
                    "POST",
                    "v2-tok",
                    {"name": "Pixel 9", "battery": 88, "charging": True},
                )
                self.assertEqual(code, 200)
                self.assertEqual(dev["phone"]["battery"], 88)
                self.assertTrue(dev["phone"]["charging"])

                code, ring = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/continuity/ring",
                    "POST",
                    "v2-tok",
                    {"duration": 10},
                )
                self.assertEqual(code, 200)
                self.assertTrue(ring["ok"])

                code, rep = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/continuity/reply",
                    "POST",
                    "v2-tok",
                    {"reply_id": "msg-1", "text": "On my way!"},
                )
                self.assertEqual(code, 200)
                self.assertTrue(rep["ok"])

                # 3. Pairing info + URI
                code, pair = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/pairing/info",
                    "GET",
                    "v2-tok",
                )
                self.assertEqual(code, 200)
                self.assertTrue(pair["pair_uri"].startswith("omalink://pair?"))
                self.assertIn("token=v2-tok", pair["pair_uri"])

                # 4. Agent usage endpoint
                with mock.patch.object(
                    omarchy_control,
                    "read_agents_usage_sync",
                    return_value=[{"id": "agy", "name": "Antigravity", "today_prompts": 5, "limits": []}],
                ):
                    code, usage = await asyncio.to_thread(
                        _http_json,
                        f"http://127.0.0.1:{port}/api/agents/usage",
                        "GET",
                        "v2-tok",
                    )
                    self.assertEqual(code, 200)
                    self.assertEqual(usage["agents"][0]["id"], "agy")
        finally:
            await bridge.stop()

    def test_sessions_discovery_transcript_and_pending_question(self) -> None:
        import sqlite3
        import omarchy_sessions

        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            db_path = root / "conversation_summaries.db"
            conn = sqlite3.connect(str(db_path))
            conn.execute(
                """
                CREATE TABLE conversation_summaries (
                    conversation_id text PRIMARY KEY,
                    title text NOT NULL DEFAULT "",
                    preview text NOT NULL DEFAULT "",
                    step_count integer NOT NULL DEFAULT 0,
                    last_modified_time text NOT NULL,
                    workspace_uris text NOT NULL,
                    status text NOT NULL DEFAULT "",
                    parent_conversation_id text NOT NULL DEFAULT "",
                    not_fully_idle integer NOT NULL DEFAULT 0,
                    killed integer NOT NULL DEFAULT 0
                )
                """
            )
            conn.execute(
                """
                INSERT INTO conversation_summaries VALUES (
                    'sess-123', 'Build OmaLink Plugin', 'Ready to ship?', 4,
                    '2026-11-19 03:00:00+00:00', '["file:///home/omarchy/Projects/omalink"]',
                    'CASCADE_RUN_STATUS_WAITING_FOR_USER', '', 1, 0
                )
                """
            )
            conn.commit()
            conn.close()

            log_dir = root / "brain" / "sess-123" / ".system_generated" / "logs"
            log_dir.mkdir(parents=True)
            lines = [
                json.dumps({
                    "step_index": 1,
                    "source": "USER_EXPLICIT",
                    "type": "USER_INPUT",
                    "status": "DONE",
                    "created_at": "2026-11-19T02:59:00Z",
                    "content": "Build the plugin and ask me before publishing",
                }),
                json.dumps({
                    "step_index": 2,
                    "source": "MODEL",
                    "type": "PLANNER_RESPONSE",
                    "status": "DONE",
                    "created_at": "2026-11-19T03:00:00Z",
                    "content": "",
                    "tool_calls": [
                        {
                            "name": "ask_question",
                            "args": {
                                "questions": json.dumps([
                                    {
                                        "question": "Publish v3.1.0 now?",
                                        "options": ["Yes, ship it", "Wait"],
                                        "is_multi_select": False,
                                    }
                                ])
                            },
                        }
                    ],
                }),
            ]
            (log_dir / "transcript.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")

            sessions = omarchy_sessions.discover_sessions(limit=5, agy_root=root, claude_root=root / "none")
            self.assertEqual(len(sessions), 1)
            self.assertEqual(sessions[0]["id"], "sess-123")
            self.assertEqual(sessions[0]["state"], "needs_response")
            self.assertEqual(sessions[0]["workspace"], "/home/omarchy/Projects/omalink")
            self.assertEqual(len(sessions[0]["pending_questions"]), 1)
            self.assertEqual(sessions[0]["pending_questions"][0]["question"], "Publish v3.1.0 now?")

            tr = omarchy_sessions.read_session_transcript("agy", "sess-123", limit=10, agy_root=root)
            self.assertTrue(tr["ok"])
            self.assertEqual(len(tr["messages"]), 2)
            self.assertEqual(tr["messages"][0]["role"], "user")
            self.assertEqual(tr["messages"][1]["role"], "question")

            # Closing/dismissing removes it until new steps arrive
            closed = omarchy_sessions.close_session(
                "agy", "sess-123", step_count=4, config_dir=root / "cfg", check_live_procs=False
            )
            self.assertTrue(closed["ok"])
            after_close = omarchy_sessions.discover_sessions(
                limit=5, agy_root=root, claude_root=root / "none", config_dir=root / "cfg"
            )
            self.assertEqual(after_close, [])

    def test_session_send_and_close_http_endpoints(self) -> None:
        async def run() -> None:
            bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token="sess-tok")
            await bridge.start()
            try:
                port = bridge.bound_port
                code, res = await asyncio.to_thread(
                    _http_json,
                    f"http://127.0.0.1:{port}/api/sessions/mock/conv-42/send",
                    "POST",
                    "sess-tok",
                    {"message": "Continue building feature X", "mode": "resume"},
                )
                self.assertEqual(code, 201)
                self.assertTrue(res["ok"])
                self.assertEqual(res["task"]["conversation_id"], "conv-42")
                self.assertEqual(res["task"]["prompt"], "Continue building feature X")

                with mock.patch("omarchy_sessions.close_session", return_value={"ok": True, "session_id": "conv-42", "message": "Closed"}):
                    with mock.patch("omarchy_sessions.discover_sessions", return_value=[]):
                        code2, res2 = await asyncio.to_thread(
                            _http_json,
                            f"http://127.0.0.1:{port}/api/sessions/mock/conv-42/close",
                            "POST",
                            "sess-tok",
                            {"step_count": 4},
                        )
                        self.assertEqual(code2, 200)
                        self.assertTrue(res2["ok"])
            finally:
                await bridge.stop()

        asyncio.run(run())

    def test_security_auth_before_body_query_rejection_rate_limit_and_symlinks(self) -> None:
        import subprocess
        import omarchy_files

        # 1. Symlink safety: rename & trash act on the symlink itself, NEVER its target!
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            target_file = base / "important_target.txt"
            target_file.write_text("DO NOT TOUCH", encoding="utf-8")
            link_path = base / "my_link.txt"
            os.symlink(target_file, link_path)

            renamed = omarchy_files.rename_entry_sync(str(link_path), "renamed_link.txt")
            self.assertTrue(renamed["ok"])
            new_link = base / "renamed_link.txt"
            self.assertTrue(new_link.is_symlink())
            self.assertFalse(os.path.lexists(link_path))
            self.assertTrue(target_file.exists())
            self.assertEqual(target_file.read_text(encoding="utf-8"), "DO NOT TOUCH")

            # Verify trash invokes `gio trash -- <symlink_path>` (NOT target_file)
            called_cmds: list[list[str]] = []

            def fake_run(cmd: list[str], **_kw: object) -> subprocess.CompletedProcess[str]:
                called_cmds.append(list(cmd))
                return subprocess.CompletedProcess(cmd, 0, "", "")

            with mock.patch("shutil.which", return_value="/usr/bin/gio"):
                with mock.patch("subprocess.run", side_effect=fake_run):
                    trashed = omarchy_files.trash_entry_sync(str(new_link))
                    self.assertTrue(trashed["ok"])
            self.assertEqual(called_cmds[0][-1], str(new_link))
            self.assertNotEqual(called_cmds[0][-1], str(target_file.resolve()))
            self.assertTrue(target_file.exists())

        # 2. Unauthenticated huge Content-Length rejected IMMEDIATELY without buffering,
        #    query-string ?token= rejected, and rate-limiter enforces 429
        async def run_net_checks() -> None:
            strong_tok = generate_pairing_token()
            bridge = OmarchyWizardBridge(host="127.0.0.1", port=0, token=strong_tok)
            await bridge.start()
            port = bridge.bound_port
            try:
                # Query-string token must be rejected
                r, w = await asyncio.open_connection("127.0.0.1", port)
                w.write(
                    f"GET /api/status?token={strong_tok} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n".encode()
                )
                await w.drain()
                line = (await asyncio.wait_for(r.readline(), timeout=2.0)).decode()
                self.assertIn("401", line)
                w.close()
                await w.wait_closed()

                # Unauthenticated POST claiming 500 MB body (sending 0 body bytes) must return 401 immediately!
                r2, w2 = await asyncio.open_connection("127.0.0.1", port)
                w2.write(
                    (
                        f"POST /api/files/upload HTTP/1.1\r\n"
                        f"Host: 127.0.0.1:{port}\r\n"
                        "Content-Length: 500000000\r\n\r\n"
                    ).encode()
                )
                await w2.drain()
                line2 = (await asyncio.wait_for(r2.readline(), timeout=2.0)).decode()
                self.assertIn("401", line2)
                w2.close()
                await w2.wait_closed()

                # Trigger auth rate-limit (429) after repeated failures
                got_429 = False
                for _ in range(10):
                    rr, ww = await asyncio.open_connection("127.0.0.1", port)
                    ww.write(
                        f"GET /api/status HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nAuthorization: Bearer wrong\r\n\r\n".encode()
                    )
                    await ww.drain()
                    st = (await asyncio.wait_for(rr.readline(), timeout=2.0)).decode()
                    ww.close()
                    await ww.wait_closed()
                    if "429" in st:
                        got_429 = True
                        break
                self.assertTrue(got_429, "Expected 429 Too Many Requests after repeated failed auth attempts")
            finally:
                await bridge.stop()

        asyncio.run(run_net_checks())


if __name__ == "__main__":
    unittest.main()
