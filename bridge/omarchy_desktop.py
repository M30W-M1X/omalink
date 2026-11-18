#!/usr/bin/env python3
"""Remote Desktop streaming and Wayland input injection for Omarchy Wizard Bridge.

Pure Python 3 stdlib + system Wayland utilities (grim, wtype, hyprctl):
  - Captures Hyprland monitor frames as JPEG via `grim -c` and streams them over
    binary WebSocket frames with blake2b change-dedup and event-triggered wakeups.
  - Injects mouse motion, clicks, drags, and scroll events directly into Hyprland's
    `zwlr_virtual_pointer_manager_v1` global over the Wayland UNIX socket.
  - Injects text and modifier key chords via `wtype`.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import time
from typing import Any


BTN_LEFT = 0x110
BTN_RIGHT = 0x111
BTN_MIDDLE = 0x112

_BUTTON_CODES = {
    "left": BTN_LEFT,
    "right": BTN_RIGHT,
    "middle": BTN_MIDDLE,
}

_MODIFIER_MAP = {
    "ctrl": "ctrl",
    "control": "ctrl",
    "alt": "alt",
    "shift": "shift",
    "super": "logo",
    "logo": "logo",
    "win": "logo",
    "altgr": "altgr",
}

_SAFE_KEYSYMS = {
    "Return",
    "BackSpace",
    "Tab",
    "Escape",
    "space",
    "Delete",
    "Up",
    "Down",
    "Left",
    "Right",
    "Home",
    "End",
    "Prior",
    "Next",
    "Insert",
    "Super_L",
    "F1",
    "F2",
    "F3",
    "F4",
    "F5",
    "F6",
    "F7",
    "F8",
    "F9",
    "F10",
    "F11",
    "F12",
}


def resolve_wayland_env() -> dict[str, str]:
    """Build an environment guaranteed to point at the user's Wayland socket."""
    env = os.environ.copy()
    runtime_dir = env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    env["XDG_RUNTIME_DIR"] = runtime_dir
    if not env.get("WAYLAND_DISPLAY"):
        rt_path = Path(runtime_dir)
        if rt_path.is_dir():
            for candidate in sorted(rt_path.glob("wayland-*")):
                if not candidate.name.endswith(".lock") and candidate.is_socket():
                    env["WAYLAND_DISPLAY"] = candidate.name
                    break
    return env


def clamp_stream_params(scale: Any, quality: Any, fps: Any) -> tuple[float, int, int]:
    """Clamp desktop stream scale, JPEG quality, and target FPS."""
    try:
        sc = float(scale)
    except (TypeError, ValueError):
        sc = 0.35
    try:
        q = int(quality)
    except (TypeError, ValueError):
        q = 58
    try:
        f = int(fps)
    except (TypeError, ValueError):
        f = 4
    return max(0.15, min(sc, 1.0)), max(20, min(q, 95)), max(1, min(f, 10))


def detect_desktop_capabilities() -> dict[str, Any]:
    """Report available Wayland capture, input, and optional VNC tools."""
    env = resolve_wayland_env()
    runtime = Path(env.get("XDG_RUNTIME_DIR", ""))
    wl_name = env.get("WAYLAND_DISPLAY", "")
    wl_socket = bool(wl_name and (runtime / wl_name).exists())
    return {
        "wayland_socket": wl_socket,
        "grim": shutil.which("grim") is not None,
        "wtype": shutil.which("wtype") is not None,
        "hyprctl": shutil.which("hyprctl") is not None,
        "wayvnc": shutil.which("wayvnc") is not None,
    }


def _pack_wl_str(value: str) -> bytes:
    raw = value.encode("utf-8") + b"\x00"
    pad = (-len(raw)) % 4
    return struct.pack("<I", len(raw)) + raw + (b"\x00" * pad)


def _pack_wl_msg(obj_id: int, opcode: int, payload: bytes = b"") -> bytes:
    total = 8 + len(payload)
    return struct.pack("<II", obj_id, (opcode & 0xFFFF) | (total << 16)) + payload


class WaylandVirtualPointer:
    """Lightweight pure-Python client for `zwlr_virtual_pointer_manager_v1`."""

    def __init__(self, env: dict[str, str] | None = None) -> None:
        self.env = env or resolve_wayland_env()
        self._sock: socket.socket | None = None
        self._pointer_id: int = 0
        self._mgr_id: int = 0
        self._sync_seq: int = 10

    @property
    def connected(self) -> bool:
        return self._sock is not None and self._pointer_id > 0

    def connect(self) -> bool:
        """Connect to the compositor Wayland socket and create a virtual pointer."""
        self.close()
        runtime_dir = self.env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        wl_display = self.env.get("WAYLAND_DISPLAY") or ""
        if not wl_display:
            return False
        sock_path = os.path.join(runtime_dir, wl_display)
        if not os.path.exists(sock_path):
            return False

        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(1.5)
        try:
            sock.connect(sock_path)
            # wl_display(1).get_registry(opcode=1) -> registry(2), then sync(opcode=0) -> cb(3)
            sock.sendall(
                _pack_wl_msg(1, 1, struct.pack("<I", 2))
                + _pack_wl_msg(1, 0, struct.pack("<I", 3))
            )

            buf = bytearray()
            globals_map: dict[str, tuple[int, int]] = {}
            done = False
            while not done:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                buf.extend(chunk)
                while len(buf) >= 8:
                    obj, word = struct.unpack("<II", buf[:8])
                    size, op = word >> 16, word & 0xFFFF
                    if size < 8 or len(buf) < size:
                        break
                    body = bytes(buf[8:size])
                    del buf[:size]
                    if obj == 2 and op == 0 and len(body) >= 12:
                        name, slen = struct.unpack("<II", body[:8])
                        iface = body[8 : 8 + slen].rstrip(b"\x00").decode("utf-8", errors="ignore")
                        off = 8 + slen + ((-slen) % 4)
                        if off + 4 <= len(body):
                            ver = struct.unpack("<I", body[off : off + 4])[0]
                            globals_map[iface] = (name, ver)
                    elif obj == 3 and op == 0:
                        done = True

            if "zwlr_virtual_pointer_manager_v1" not in globals_map:
                sock.close()
                return False

            seat_id = 0
            next_id = 4
            bind_msgs = bytearray()
            if "wl_seat" in globals_map:
                seat_name, seat_ver = globals_map["wl_seat"]
                seat_id = next_id
                next_id += 1
                bind_msgs.extend(
                    _pack_wl_msg(
                        2,
                        0,
                        struct.pack("<I", seat_name)
                        + _pack_wl_str("wl_seat")
                        + struct.pack("<II", min(seat_ver, 5), seat_id),
                    )
                )

            vpm_name, vpm_ver = globals_map["zwlr_virtual_pointer_manager_v1"]
            mgr_id = next_id
            next_id += 1
            ptr_id = next_id
            next_id += 1
            sync_id = next_id

            bind_msgs.extend(
                _pack_wl_msg(
                    2,
                    0,
                    struct.pack("<I", vpm_name)
                    + _pack_wl_str("zwlr_virtual_pointer_manager_v1")
                    + struct.pack("<II", min(vpm_ver, 2), mgr_id),
                )
            )
            # zwlr_virtual_pointer_manager_v1.create_virtual_pointer(seat, new_id) -> opcode 0
            bind_msgs.extend(_pack_wl_msg(mgr_id, 0, struct.pack("<II", seat_id, ptr_id)))
            bind_msgs.extend(_pack_wl_msg(1, 0, struct.pack("<I", sync_id)))
            sock.sendall(bytes(bind_msgs))

            self._sock = sock
            self._mgr_id = mgr_id
            self._pointer_id = ptr_id
            self._sync_seq = sync_id + 1
            return True
        except OSError:
            try:
                sock.close()
            except OSError:
                pass
            return False

    def _send(self, payload: bytes) -> bool:
        if not self.connected and not self.connect():
            return False
        assert self._sock is not None
        try:
            self._sock.sendall(payload)
            return True
        except OSError:
            self.close()
            if self.connect() and self._sock is not None:
                try:
                    self._sock.sendall(payload)
                    return True
                except OSError:
                    self.close()
            return False

    def _ts(self) -> int:
        return int(time.monotonic() * 1000) & 0xFFFFFFFF

    def move_rel(self, dx: float, dy: float) -> bool:
        """Move pointer by relative pixel displacement (Wayland 24.8 fixed-point)."""
        fx = int(round(float(dx) * 256.0))
        fy = int(round(float(dy) * 256.0))
        if fx == 0 and fy == 0:
            return True
        msg = _pack_wl_msg(
            self._pointer_id,
            0,  # motion (relative)
            struct.pack("<Iii", self._ts(), fx, fy),
        ) + _pack_wl_msg(self._pointer_id, 4)  # frame
        return self._send(msg)

    def move_abs(self, x: int, y: int, extent_w: int, extent_h: int) -> bool:
        """Move pointer in absolute global space [0..extent_w] x [0..extent_h]."""
        if extent_w <= 0 or extent_h <= 0:
            return False
        cx = max(0, min(int(x), extent_w - 1))
        cy = max(0, min(int(y), extent_h - 1))
        msg = _pack_wl_msg(
            self._pointer_id,
            1,  # motion_absolute
            struct.pack("<IIIII", self._ts(), cx, cy, extent_w, extent_h),
        ) + _pack_wl_msg(self._pointer_id, 4)  # frame
        return self._send(msg)

    def button(self, button_name: str, pressed: bool) -> bool:
        """Press or release a mouse button."""
        code = _BUTTON_CODES.get(button_name.lower(), BTN_LEFT)
        state = 1 if pressed else 0
        msg = _pack_wl_msg(
            self._pointer_id,
            2,  # button
            struct.pack("<III", self._ts(), code, state),
        ) + _pack_wl_msg(self._pointer_id, 4)  # frame
        return self._send(msg)

    def scroll(self, dx: float = 0.0, dy: float = 0.0) -> bool:
        """Emit smooth scroll axis events in Wayland 24.8 fixed-point units."""
        buf = bytearray()
        ts = self._ts()
        if abs(dy) > 0.01:
            fixed_y = int(round(dy * 256.0))
            buf.extend(_pack_wl_msg(self._pointer_id, 3, struct.pack("<IIi", ts, 0, fixed_y)))
        if abs(dx) > 0.01:
            fixed_x = int(round(dx * 256.0))
            buf.extend(_pack_wl_msg(self._pointer_id, 3, struct.pack("<IIi", ts, 1, fixed_x)))
        if not buf:
            return True
        buf.extend(_pack_wl_msg(self._pointer_id, 4))  # frame
        return self._send(bytes(buf))

    def close(self) -> None:
        if self._sock is not None:
            try:
                if self._pointer_id:
                    self._sock.sendall(_pack_wl_msg(self._pointer_id, 8))  # destroy pointer
                if self._mgr_id:
                    self._sock.sendall(_pack_wl_msg(self._mgr_id, 1))  # destroy manager
            except OSError:
                pass
            try:
                self._sock.close()
            except OSError:
                pass
        self._sock = None
        self._pointer_id = 0
        self._mgr_id = 0


def read_monitors_and_workspaces_sync(env: dict[str, str] | None = None) -> dict[str, Any]:
    """Query Hyprland monitor layout and active workspaces."""
    resolved_env = env or resolve_wayland_env()
    monitors: list[dict[str, Any]] = []
    workspaces: list[dict[str, Any]] = []

    if shutil.which("hyprctl"):
        try:
            res = subprocess.run(
                ["hyprctl", "monitors", "-j"],
                capture_output=True,
                text=True,
                timeout=3.0,
                env=resolved_env,
            )
            if res.returncode == 0 and res.stdout.strip():
                raw_monitors = json.loads(res.stdout)
                if isinstance(raw_monitors, list):
                    for m in raw_monitors:
                        monitors.append({
                            "name": m.get("name", ""),
                            "width": int(m.get("width", 1920)),
                            "height": int(m.get("height", 1080)),
                            "x": int(m.get("x", 0)),
                            "y": int(m.get("y", 0)),
                            "scale": float(m.get("scale", 1.0)),
                            "focused": bool(m.get("focused", False)),
                            "active_workspace": (m.get("activeWorkspace") or {}).get("id", 1),
                        })
        except Exception:
            pass

        try:
            res = subprocess.run(
                ["hyprctl", "workspaces", "-j"],
                capture_output=True,
                text=True,
                timeout=3.0,
                env=resolved_env,
            )
            if res.returncode == 0 and res.stdout.strip():
                raw_ws = json.loads(res.stdout)
                if isinstance(raw_ws, list):
                    for ws in sorted(raw_ws, key=lambda item: int(item.get("id", 0))):
                        ws_id = int(ws.get("id", 0))
                        if ws_id > 0:
                            workspaces.append({
                                "id": ws_id,
                                "name": str(ws.get("name", ws_id)),
                                "windows": int(ws.get("windows", 0)),
                            })
        except Exception:
            pass

    if not monitors:
        monitors = [{
            "name": "default",
            "width": 1920,
            "height": 1080,
            "x": 0,
            "y": 0,
            "scale": 1.0,
            "focused": True,
            "active_workspace": 1,
        }]

    return {"monitors": monitors, "workspaces": workspaces}


def map_normalized_point(
    nx: float,
    ny: float,
    monitors: list[dict[str, Any]],
    selected_output: str | None = None,
) -> tuple[int, int, int, int]:
    """Map normalized [0..1] coords inside `selected_output` to virtual-pointer extent."""
    clamped_x = max(0.0, min(float(nx), 1.0))
    clamped_y = max(0.0, min(float(ny), 1.0))

    min_x = min(m.get("x", 0) for m in monitors)
    min_y = min(m.get("y", 0) for m in monitors)
    max_x = max(m.get("x", 0) + m.get("width", 1920) for m in monitors)
    max_y = max(m.get("y", 0) + m.get("height", 1080) for m in monitors)
    total_w = max(1, max_x - min_x)
    total_h = max(1, max_y - min_y)

    target = None
    if selected_output:
        for m in monitors:
            if m.get("name") == selected_output:
                target = m
                break
    if target is None:
        target = next((m for m in monitors if m.get("focused")), monitors[0])

    tx = int(target.get("x", 0)) - min_x
    ty = int(target.get("y", 0)) - min_y
    tw = max(1, int(target.get("width", 1920)))
    th = max(1, int(target.get("height", 1080)))

    abs_x = int(round(tx + clamped_x * (tw - 1)))
    abs_y = int(round(ty + clamped_y * (th - 1)))
    return abs_x, abs_y, total_w, total_h


async def capture_frame_jpeg(
    output_name: str | None,
    scale: float,
    quality: int,
    env: dict[str, str],
) -> bytes | None:
    """Capture a single Wayland screen JPEG using `grim -c`."""
    if not shutil.which("grim"):
        return None
    cmd = ["grim", "-c", "-t", "jpeg", "-q", str(quality), "-s", f"{scale:.2f}"]
    if output_name and output_name != "default":
        cmd.extend(["-o", output_name])
    cmd.append("-")
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
            env=env,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=3.0)
        if proc.returncode == 0 and stdout:
            return stdout
    except (asyncio.TimeoutError, OSError):
        pass
    return None


async def inject_keyboard(
    text: str | None = None,
    key: str | None = None,
    modifiers: list[str] | None = None,
    env: dict[str, str] | None = None,
) -> bool:
    """Type Unicode text or press an XKB keysym with optional modifiers via `wtype`."""
    if not shutil.which("wtype"):
        return False
    resolved_env = env or resolve_wayland_env()

    if text:
        cmd = ["wtype", "--", text]
    elif key:
        cmd = ["wtype"]
        mods = [_MODIFIER_MAP[m.lower()] for m in (modifiers or []) if m.lower() in _MODIFIER_MAP]
        for m in mods:
            cmd.extend(["-M", m])
        if key in _SAFE_KEYSYMS or (len(key) == 1 and key.isprintable()):
            cmd.extend(["-k", key])
        else:
            return False
        for m in reversed(mods):
            cmd.extend(["-m", m])
    else:
        return False

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
            env=resolved_env,
        )
        await asyncio.wait_for(proc.wait(), timeout=2.0)
        return proc.returncode == 0
    except (asyncio.TimeoutError, OSError):
        return False


async def handle_desktop_websocket(
    ws: Any,
    query: dict[str, list[str]],
) -> None:
    """Bridge an authenticated `/ws/desktop` WebSocket to screen capture and input injection."""
    env = resolve_wayland_env()
    scale, quality, fps = clamp_stream_params(
        (query.get("scale") or ["0.35"])[0],
        (query.get("quality") or ["58"])[0],
        (query.get("fps") or ["4"])[0],
    )
    selected_output = (query.get("output") or [""])[0].strip() or None
    paused = ((query.get("paused") or ["0"])[0]).lower() in {"1", "true", "yes"}
    force_refresh = not paused
    last_digest = b""
    wake_event = asyncio.Event()

    layout = await asyncio.to_thread(read_monitors_and_workspaces_sync, env)
    monitors = layout["monitors"]
    workspaces = layout["workspaces"]
    if not selected_output:
        focused = next((m for m in monitors if m.get("focused")), monitors[0])
        selected_output = focused.get("name") or None

    caps = detect_desktop_capabilities()
    pointer = WaylandVirtualPointer(env=env)
    pointer_ok = await asyncio.to_thread(pointer.connect)
    caps["virtual_pointer"] = pointer_ok

    active_mon = next((m for m in monitors if m.get("name") == selected_output), monitors[0])

    await ws.send_json({
        "type": "ready",
        "monitor": active_mon,
        "monitors": monitors,
        "workspaces": workspaces,
        "output": selected_output or active_mon.get("name", "default"),
        "scale": scale,
        "quality": quality,
        "fps": fps,
        "capabilities": caps,
    })

    async def _capture_loop() -> None:
        nonlocal force_refresh, last_digest
        while not ws.closed:
            if paused:
                wake_event.clear()
                try:
                    await asyncio.wait_for(wake_event.wait(), timeout=0.5)
                except asyncio.TimeoutError:
                    pass
                continue

            t0 = time.monotonic()
            frame = await capture_frame_jpeg(selected_output, scale, quality, env)
            if ws.closed:
                break
            if frame:
                digest = hashlib.blake2b(frame, digest_size=16).digest()
                if force_refresh or digest != last_digest:
                    last_digest = digest
                    force_refresh = False
                    await ws.send_frame(0x2, frame)

            elapsed = time.monotonic() - t0
            delay = max(0.04, (1.0 / fps) - elapsed)
            wake_event.clear()
            try:
                await asyncio.wait_for(wake_event.wait(), timeout=delay)
            except asyncio.TimeoutError:
                pass

    async def _trigger_repaint(delay_s: float = 0.06) -> None:
        nonlocal force_refresh
        await asyncio.sleep(delay_s)
        force_refresh = True
        wake_event.set()

    async def _recv_loop() -> None:
        nonlocal scale, quality, fps, selected_output, paused, force_refresh, monitors, workspaces, active_mon
        while not ws.closed:
            frame = await ws.read_frame()
            if frame is None:
                break
            opcode, payload = frame
            if opcode == 0x8:
                break
            if opcode == 0x9:
                await ws.send_frame(0xA, payload)
                continue
            if opcode != 0x1:
                continue
            try:
                msg = json.loads(payload.decode("utf-8"))
            except Exception:
                continue
            if not isinstance(msg, dict):
                continue

            mtype = msg.get("type")
            if mtype == "pointer":
                action = str(msg.get("action", "move"))
                btn = str(msg.get("button", "left"))
                has_coords = msg.get("x") is not None and msg.get("y") is not None
                if has_coords:
                    ax, ay, ew, eh = map_normalized_point(
                        msg.get("x", 0.5),
                        msg.get("y", 0.5),
                        monitors,
                        selected_output,
                    )
                    await asyncio.to_thread(pointer.move_abs, ax, ay, ew, eh)

                if action == "tap":
                    await asyncio.to_thread(pointer.button, btn, True)
                    await asyncio.sleep(0.03)
                    await asyncio.to_thread(pointer.button, btn, False)
                    asyncio.create_task(_trigger_repaint(0.08))
                elif action == "double_tap":
                    for _ in range(2):
                        await asyncio.to_thread(pointer.button, btn, True)
                        await asyncio.sleep(0.025)
                        await asyncio.to_thread(pointer.button, btn, False)
                        await asyncio.sleep(0.05)
                    asyncio.create_task(_trigger_repaint(0.08))
                elif action == "right_click":
                    await asyncio.to_thread(pointer.button, "right", True)
                    await asyncio.sleep(0.03)
                    await asyncio.to_thread(pointer.button, "right", False)
                    asyncio.create_task(_trigger_repaint(0.08))
                elif action == "down":
                    await asyncio.to_thread(pointer.button, btn, True)
                elif action == "up":
                    await asyncio.to_thread(pointer.button, btn, False)
                    asyncio.create_task(_trigger_repaint(0.08))
                elif action == "scroll":
                    dx = float(msg.get("dx", 0.0))
                    dy = float(msg.get("dy", 0.0))
                    await asyncio.to_thread(pointer.scroll, dx, dy)
                    if not paused:
                        asyncio.create_task(_trigger_repaint(0.06))
                elif action == "relative":
                    dx = float(msg.get("dx", 0.0))
                    dy = float(msg.get("dy", 0.0))
                    await asyncio.to_thread(pointer.move_rel, dx, dy)
                elif action == "move":
                    if not paused:
                        force_refresh = True
                        wake_event.set()

            elif mtype == "key":
                ok = await inject_keyboard(
                    text=msg.get("text") if isinstance(msg.get("text"), str) else None,
                    key=msg.get("key") if isinstance(msg.get("key"), str) else None,
                    modifiers=msg.get("modifiers") if isinstance(msg.get("modifiers"), list) else None,
                    env=env,
                )
                if ok:
                    asyncio.create_task(_trigger_repaint(0.08))

            elif mtype == "workspace":
                try:
                    ws_id = int(msg.get("id", 1))
                except (TypeError, ValueError):
                    ws_id = 1
                if 1 <= ws_id <= 20 and shutil.which("hyprctl"):
                    proc = await asyncio.create_subprocess_exec(
                        "hyprctl",
                        "dispatch",
                        "workspace",
                        str(ws_id),
                        stdout=asyncio.subprocess.DEVNULL,
                        stderr=asyncio.subprocess.DEVNULL,
                        env=env,
                    )
                    await proc.wait()
                    layout = await asyncio.to_thread(read_monitors_and_workspaces_sync, env)
                    monitors = layout["monitors"]
                    workspaces = layout["workspaces"]
                    await ws.send_json({
                        "type": "layout",
                        "monitor": active_mon,
                        "monitors": monitors,
                        "workspaces": workspaces,
                    })
                    asyncio.create_task(_trigger_repaint(0.12))

            elif mtype == "config":
                scale, quality, fps = clamp_stream_params(
                    msg.get("scale", scale),
                    msg.get("quality", quality),
                    msg.get("fps", fps),
                )
                if "paused" in msg:
                    paused = bool(msg["paused"])
                if isinstance(msg.get("output"), str) and msg["output"].strip():
                    selected_output = msg["output"].strip()
                    active_mon = next(
                        (m for m in monitors if m.get("name") == selected_output),
                        active_mon,
                    )
                force_refresh = True
                wake_event.set()

            elif mtype == "refresh":
                force_refresh = True
                wake_event.set()

            elif mtype == "ping":
                await ws.send_json({"type": "pong"})

    cap_task = asyncio.create_task(_capture_loop())
    recv_task = asyncio.create_task(_recv_loop())
    try:
        done, pending = await asyncio.wait(
            {cap_task, recv_task},
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        for task in done:
            task.result()
    except asyncio.CancelledError:
        pass
    finally:
        await asyncio.to_thread(pointer.close)
        await ws.close()
