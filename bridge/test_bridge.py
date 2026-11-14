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

            # Connect WebSocket client
            ws_reader, ws_writer = await asyncio.open_connection("127.0.0.1", port)
            ws_key = base64.b64encode(os.urandom(16)).decode("ascii")
            handshake = (
                "GET /ws?token=secret-wizard-token HTTP/1.1\r\n"
                f"Host: 127.0.0.1:{port}\r\n"
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

    def test_generated_token_is_five_digits(self) -> None:
        token = generate_pairing_token()
        self.assertEqual(len(token), 5)
        self.assertTrue(token.isdigit())

        with tempfile.TemporaryDirectory() as tmpdir:
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": tmpdir}, clear=False):
                os.environ.pop("OMARCHY_WIZARD_TOKEN", None)
                created = load_or_create_token()
                self.assertEqual(len(created), 5)
                self.assertTrue(created.isdigit())
                token_path = Path(tmpdir) / "omarchy-wizard" / "token"
                self.assertEqual(token_path.read_text(encoding="utf-8").strip(), created)
                self.assertEqual(load_or_create_token(), created)


if __name__ == "__main__":
    unittest.main()
