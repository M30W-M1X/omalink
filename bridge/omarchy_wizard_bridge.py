#!/usr/bin/env python3
"""Omarchy Wizard Bridge: HTTP + WebSocket control server for Omarchy AI agents.

Zero third-party dependencies (Python 3.11+ standard library only).
Exposes a token-authenticated REST API and RFC 6455 WebSocket stream so the
Omarchy Wizard Flutter Android app can launch, monitor, and cancel AI agent
tasks running on an Omarchy Linux machine and receive task-completion alerts.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import hmac
from http import HTTPStatus
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import struct
import subprocess
import sys
from typing import Any
from urllib.parse import parse_qs, urlparse
import uuid

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
DEFAULT_PORT = 7842
MAX_LOG_EVENTS = 500
MAX_TASKS = 100


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_config_dir() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "omarchy-wizard"


def load_or_create_token(explicit_token: str | None = None) -> str:
    if explicit_token:
        return explicit_token.strip()
    env_token = os.environ.get("OMARCHY_WIZARD_TOKEN", "").strip()
    if env_token:
        return env_token
    cfg_dir = get_config_dir()
    token_file = cfg_dir / "token"
    if token_file.exists():
        saved = token_file.read_text(encoding="utf-8").strip()
        if saved:
            return saved
    cfg_dir.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(24)
    token_file.write_text(token + "\n", encoding="utf-8")
    os.chmod(token_file, 0o600)
    return token


def read_omarchy_info() -> dict[str, str]:
    info: dict[str, str] = {
        "hostname": socket.gethostname(),
        "os_name": "Omarchy",
        "os_version": "unknown",
    }
    os_release = Path("/etc/os-release")
    if os_release.exists():
        for line in os_release.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" not in line:
                continue
            key, val = line.split("=", 1)
            val = val.strip().strip('"')
            if key == "NAME":
                info["os_name"] = val
            elif key == "VERSION_ID":
                info["os_version"] = val
    return info


def get_default_agent() -> str:
    if shutil.which("omarchy-default-agent"):
        try:
            res = subprocess.run(
                ["omarchy-default-agent"],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            out = res.stdout.strip()
            if out:
                return out
        except Exception:
            pass
    agent_file = Path.home() / ".config" / "omarchy" / "defaults" / "agent"
    if agent_file.exists():
        saved = agent_file.read_text(encoding="utf-8").strip()
        if saved:
            return saved
    return "agy"


def detect_available_agents() -> list[str]:
    candidates = ["agy", "claude", "codex", "kimi", "opencode", "qwen", "gemini", "pi"]
    found = [name for name in candidates if shutil.which(name)]
    return found or ["agy"]


def detect_workspaces() -> list[str]:
    home = Path.home()
    candidates = [home / "Work", home / "Projects", home]
    existing = [str(p) for p in candidates if p.exists() and p.is_dir()]
    projects_dir = home / "Projects"
    if projects_dir.exists() and projects_dir.is_dir():
        for child in sorted(projects_dir.iterdir()):
            if child.is_dir() and not child.name.startswith("."):
                existing.append(str(child))
    # Deduplicate while preserving order
    return list(dict.fromkeys(existing))


def build_agent_command(
    agent: str,
    prompt: str,
    mode: str = "auto",
    effort: str = "high",
    conversation_id: str | None = None,
) -> list[str]:
    """Build the CLI command for the requested Omarchy AI agent."""
    if agent == "mock":
        script = (
            "import json, sys, time; "
            "print(json.dumps({'type':'assistant','message':'Channeling arcane runes...'}), flush=True); "
            "time.sleep(0.15); "
            "print(json.dumps({'type':'result','result':'Spell completed for: ' + sys.argv[1]}), flush=True)"
        )
        return [sys.executable, "-c", script, prompt]

    if agent == "agy":
        cmd = [
            "agy",
            "-p",
            "--output-format",
            "stream-json",
            "--dangerously-skip-permissions",
        ]
        if mode in {"auto", "accept-edits", "plan"}:
            cmd.extend(["--mode", mode])
        if effort in {"low", "medium", "high", "xhigh", "max"}:
            cmd.extend(["--effort", effort])
        if conversation_id:
            cmd.extend(["--conversation", conversation_id])
        cmd.append(prompt)
        return cmd

    if agent == "claude":
        cmd = ["claude", "-p", "--output-format", "stream-json", "--verbose"]
        if mode == "plan":
            cmd.extend(["--permission-mode", "plan"])
        elif mode == "accept-edits":
            cmd.extend(["--permission-mode", "acceptEdits"])
        else:
            cmd.extend(["--permission-mode", "bypassPermissions"])
        if conversation_id:
            cmd.extend(["--resume", conversation_id])
        cmd.extend(["--", prompt])
        return cmd

    if agent == "codex":
        return ["codex", "exec", "--json", prompt]

    if agent == "kimi":
        return ["kimi", "--print", "--prompt", prompt]

    if agent == "opencode":
        return ["opencode", "run", prompt]

    # Generic fallback via omarchy-agent-prompt or direct binary
    return [agent, prompt]


def parse_agent_output_line(line: str, stream: str = "stdout") -> dict[str, Any]:
    """Normalize raw stdout/stderr or NDJSON from an agent into a structured event."""
    stripped = line.strip()
    base: dict[str, Any] = {
        "ts": utc_now_iso(),
        "stream": stream,
        "kind": "stderr" if stream == "stderr" else "text",
        "text": stripped,
    }
    if not stripped:
        return base

    if stripped.startswith("{"):
        try:
            payload = json.loads(stripped)
            if isinstance(payload, dict):
                ev_type = str(payload.get("type") or payload.get("event") or "json")
                base["raw"] = payload
                base["kind"] = ev_type

                if "conversation_id" in payload and payload["conversation_id"]:
                    base["conversation_id"] = str(payload["conversation_id"])
                elif "session_id" in payload and payload["session_id"]:
                    base["conversation_id"] = str(payload["session_id"])

                # Extract readable text across common stream-json shapes
                text = _extract_readable_text(payload)
                if text:
                    base["text"] = text
                return base
        except json.JSONDecodeError:
            pass
    return base


def _extract_readable_text(payload: dict[str, Any]) -> str:
    for key in ("result", "message", "text", "content", "delta", "error"):
        val = payload.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
        if isinstance(val, dict):
            nested = val.get("content") or val.get("text")
            if isinstance(nested, str) and nested.strip():
                return nested.strip()
            if isinstance(nested, list):
                parts = [
                    str(item.get("text", ""))
                    for item in nested
                    if isinstance(item, dict) and item.get("text")
                ]
                joined = "\n".join(p for p in parts if p).strip()
                if joined:
                    return joined
    if "tool_name" in payload or "name" in payload:
        name = payload.get("tool_name") or payload.get("name")
        return f"Using tool: {name}"
    return ""


@dataclass
class AgentTask:
    id: str
    prompt: str
    agent: str
    mode: str
    effort: str
    cwd: str
    status: str = "running"  # running | completed | failed | cancelled
    created_at: str = field(default_factory=utc_now_iso)
    finished_at: str | None = None
    exit_code: int | None = None
    summary: str = ""
    conversation_id: str | None = None
    events: list[dict[str, Any]] = field(default_factory=list)
    process: asyncio.subprocess.Process | None = field(default=None, repr=False)

    def add_event(self, event: dict[str, Any]) -> None:
        self.events.append(event)
        if len(self.events) > MAX_LOG_EVENTS:
            self.events = self.events[-MAX_LOG_EVENTS:]
        conv_id = event.get("conversation_id")
        if conv_id and not self.conversation_id:
            self.conversation_id = str(conv_id)
        if event.get("kind") in {"result", "assistant", "text"} and event.get("text"):
            self.summary = str(event["text"])[:280]

    def duration_seconds(self) -> float | None:
        if not self.finished_at:
            return None
        start = datetime.fromisoformat(self.created_at)
        end = datetime.fromisoformat(self.finished_at)
        return round((end - start).total_seconds(), 2)

    def to_dict(self, include_events: bool = False) -> dict[str, Any]:
        data: dict[str, Any] = {
            "id": self.id,
            "prompt": self.prompt,
            "agent": self.agent,
            "mode": self.mode,
            "effort": self.effort,
            "cwd": self.cwd,
            "status": self.status,
            "created_at": self.created_at,
            "finished_at": self.finished_at,
            "duration_seconds": self.duration_seconds(),
            "exit_code": self.exit_code,
            "summary": self.summary,
            "conversation_id": self.conversation_id,
            "event_count": len(self.events),
        }
        if include_events:
            data["events"] = self.events
        return data


class WebSocketClient:
    """Minimal RFC 6455 WebSocket connection over asyncio StreamReader/StreamWriter."""

    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.reader = reader
        self.writer = writer
        self.closed = False
        self._send_lock = asyncio.Lock()

    async def send_json(self, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        await self.send_frame(0x1, data)

    async def send_frame(self, opcode: int, payload: bytes = b"") -> None:
        if self.closed:
            return
        async with self._send_lock:
            if self.closed:
                return
            header = bytearray([0x80 | (opcode & 0x0F)])
            length = len(payload)
            if length < 126:
                header.append(length)
            elif length < 65536:
                header.append(126)
                header.extend(struct.pack("!H", length))
            else:
                header.append(127)
                header.extend(struct.pack("!Q", length))
            try:
                self.writer.write(bytes(header) + payload)
                await self.writer.drain()
            except (ConnectionError, OSError):
                self.closed = True

    async def read_frame(self) -> tuple[int, bytes] | None:
        try:
            b1, b2 = await self.reader.readexactly(2)
        except (asyncio.IncompleteReadError, ConnectionError, OSError):
            return None
        opcode = b1 & 0x0F
        masked = bool(b2 & 0x80)
        length = b2 & 0x7F
        if length == 126:
            length = struct.unpack("!H", await self.reader.readexactly(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", await self.reader.readexactly(8))[0]
        mask_key = await self.reader.readexactly(4) if masked else b""
        payload = bytearray(await self.reader.readexactly(length))
        if masked:
            for i in range(length):
                payload[i] ^= mask_key[i % 4]
        return opcode, bytes(payload)

    async def close(self) -> None:
        if not self.closed:
            await self.send_frame(0x8, b"")
            self.closed = True
        try:
            self.writer.close()
            await self.writer.wait_closed()
        except Exception:
            pass


class OmarchyWizardBridge:
    """Core bridge server managing tasks, WebSocket broadcasts, and HTTP endpoints."""

    def __init__(self, host: str = "0.0.0.0", port: int = DEFAULT_PORT, token: str | None = None) -> None:
        self.host = host
        self.port = port
        self.token = load_or_create_token(token)
        self.tasks: dict[str, AgentTask] = {}
        self.task_order: list[str] = []
        self.ws_clients: set[WebSocketClient] = set()
        self._bg_tasks: set[asyncio.Task[None]] = set()
        self.server: asyncio.AbstractServer | None = None
        self.bound_port: int = port

    def is_authorized(self, headers: dict[str, str], query: dict[str, list[str]]) -> bool:
        auth = headers.get("authorization", "")
        if auth.lower().startswith("bearer "):
            candidate = auth[7:].strip()
            if hmac.compare_digest(candidate, self.token):
                return True
        q_tokens = query.get("token", [])
        if q_tokens and hmac.compare_digest(q_tokens[0], self.token):
            return True
        return False

    def status_payload(self) -> dict[str, Any]:
        info = read_omarchy_info()
        running = sum(1 for t in self.tasks.values() if t.status == "running")
        return {
            "ok": True,
            "bridge_version": "1.0.0",
            "hostname": info["hostname"],
            "os_name": info["os_name"],
            "os_version": info["os_version"],
            "default_agent": get_default_agent(),
            "available_agents": detect_available_agents(),
            "workspaces": detect_workspaces(),
            "running_tasks": running,
            "connected_clients": len(self.ws_clients),
            "lan_ips": detect_lan_ips(),
            "total_tasks": len(self.tasks),
        }

    async def broadcast(self, event_type: str, data: dict[str, Any]) -> None:
        if not self.ws_clients:
            return
        message = {"type": event_type, "ts": utc_now_iso(), "data": data}
        stale: list[WebSocketClient] = []
        for client in list(self.ws_clients):
            await client.send_json(message)
            if client.closed:
                stale.append(client)
        for client in stale:
            self.ws_clients.discard(client)

    async def start_task(
        self,
        prompt: str,
        agent: str | None = None,
        mode: str = "auto",
        effort: str = "high",
        cwd: str | None = None,
        conversation_id: str | None = None,
    ) -> AgentTask:
        chosen_agent = (agent or get_default_agent()).strip()
        chosen_cwd = cwd or (detect_workspaces()[0] if detect_workspaces() else str(Path.home()))
        if not Path(chosen_cwd).is_dir():
            chosen_cwd = str(Path.home())

        task_id = uuid.uuid4().hex[:12]
        task = AgentTask(
            id=task_id,
            prompt=prompt,
            agent=chosen_agent,
            mode=mode,
            effort=effort,
            cwd=chosen_cwd,
            conversation_id=conversation_id,
        )
        self.tasks[task_id] = task
        self.task_order.insert(0, task_id)
        if len(self.task_order) > MAX_TASKS:
            old_id = self.task_order.pop()
            self.tasks.pop(old_id, None)

        cmd = build_agent_command(
            agent=chosen_agent,
            prompt=prompt,
            mode=mode,
            effort=effort,
            conversation_id=conversation_id,
        )
        task.add_event({
            "ts": utc_now_iso(),
            "stream": "system",
            "kind": "system",
            "text": f"Casting via {chosen_agent} in {chosen_cwd}",
        })
        await self.broadcast("task.started", task.to_dict())
        bg = asyncio.create_task(self._run_task_subprocess(task, cmd))
        self._bg_tasks.add(bg)
        bg.add_done_callback(self._bg_tasks.discard)
        return task

    async def _run_task_subprocess(self, task: AgentTask, cmd: list[str]) -> None:
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=task.cwd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            task.process = proc

            async def pump(stream_reader: asyncio.StreamReader | None, stream_name: str) -> None:
                if stream_reader is None:
                    return
                while True:
                    raw = await stream_reader.readline()
                    if not raw:
                        break
                    line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
                    if not line.strip():
                        continue
                    event = parse_agent_output_line(line, stream=stream_name)
                    task.add_event(event)
                    await self.broadcast(
                        "task.event",
                        {
                            "task_id": task.id,
                            "event": event,
                            "conversation_id": task.conversation_id,
                        },
                    )

            await asyncio.gather(pump(proc.stdout, "stdout"), pump(proc.stderr, "stderr"))
            code = await proc.wait()
            task.exit_code = code
            task.finished_at = utc_now_iso()
            if task.status == "cancelled":
                await self.broadcast("task.cancelled", task.to_dict())
            elif code == 0:
                task.status = "completed"
                if not task.summary:
                    task.summary = "Spell finished cleanly."
                await self.broadcast("task.completed", task.to_dict())
            else:
                task.status = "failed"
                if not task.summary:
                    task.summary = f"Agent exited with code {code}."
                await self.broadcast("task.failed", task.to_dict())
        except FileNotFoundError:
            task.status = "failed"
            task.exit_code = 127
            task.finished_at = utc_now_iso()
            task.summary = f"Agent binary '{cmd[0]}' not found on Omarchy PATH."
            err_ev = {
                "ts": utc_now_iso(),
                "stream": "stderr",
                "kind": "error",
                "text": task.summary,
            }
            task.add_event(err_ev)
            await self.broadcast("task.failed", task.to_dict())
        except Exception as exc:
            task.status = "failed"
            task.exit_code = 1
            task.finished_at = utc_now_iso()
            task.summary = f"Bridge error: {exc}"
            await self.broadcast("task.failed", task.to_dict())
        finally:
            task.process = None

    async def cancel_task(self, task_id: str) -> AgentTask | None:
        task = self.tasks.get(task_id)
        if not task:
            return None
        if task.status != "running":
            return task
        task.status = "cancelled"
        task.finished_at = utc_now_iso()
        task.summary = "Cancelled by wizard."
        proc = task.process
        if proc and proc.returncode is None:
            proc.terminate()
            try:
                await asyncio.wait_for(proc.wait(), timeout=2.0)
            except asyncio.TimeoutError:
                proc.kill()
        await self.broadcast("task.cancelled", task.to_dict())
        return task

    async def start(self) -> None:
        self.server = await asyncio.start_server(self._handle_connection, self.host, self.port)
        sockets = self.server.sockets
        if sockets:
            self.bound_port = sockets[0].getsockname()[1]

    async def stop(self) -> None:
        for task in list(self.tasks.values()):
            proc = task.process
            if proc and proc.returncode is None:
                proc.terminate()
        if self._bg_tasks:
            await asyncio.gather(*list(self._bg_tasks), return_exceptions=True)
        for client in list(self.ws_clients):
            await client.close()
        self.ws_clients.clear()
        if self.server:
            self.server.close()
            await self.server.wait_closed()

    async def _handle_connection(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            raw_head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=10.0)
        except Exception:
            writer.close()
            return

        lines = raw_head.decode("utf-8", errors="replace").split("\r\n")
        if not lines or " " not in lines[0]:
            writer.close()
            return
        parts = lines[0].split(" ", 2)
        if len(parts) < 2:
            writer.close()
            return
        method, target = parts[0].upper(), parts[1]
        parsed = urlparse(target)
        path = parsed.path
        query = parse_qs(parsed.query)

        headers: dict[str, str] = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        # WebSocket upgrade on /ws
        if method == "GET" and path == "/ws" and headers.get("upgrade", "").lower() == "websocket":
            if not self.is_authorized(headers, query):
                await self._send_http_json(writer, HTTPStatus.UNAUTHORIZED, {"error": "Unauthorized"})
                return
            await self._handle_websocket(reader, writer, headers)
            return

        # Read optional HTTP body
        content_length = int(headers.get("content-length", "0") or "0")
        body_bytes = b""
        if content_length > 0:
            body_bytes = await reader.readexactly(content_length)

        if path == "/api/ping" and method == "GET":
            await self._send_http_json(
                writer, HTTPStatus.OK, {"ok": True, "app": "omarchy-wizard-bridge"}
            )
            return

        if not self.is_authorized(headers, query):
            await self._send_http_json(writer, HTTPStatus.UNAUTHORIZED, {"error": "Unauthorized"})
            return

        await self._route_http(writer, method, path, body_bytes)

    async def _route_http(
        self, writer: asyncio.StreamWriter, method: str, path: str, body_bytes: bytes
    ) -> None:
        body: dict[str, Any] = {}
        if body_bytes:
            try:
                decoded = json.loads(body_bytes.decode("utf-8"))
                if isinstance(decoded, dict):
                    body = decoded
            except json.JSONDecodeError:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"error": "Invalid JSON body"}
                )
                return

        if method == "GET" and path == "/api/status":
            await self._send_http_json(writer, HTTPStatus.OK, self.status_payload())
            return

        if method == "GET" and path == "/api/tasks":
            items = [self.tasks[tid].to_dict() for tid in self.task_order if tid in self.tasks]
            await self._send_http_json(writer, HTTPStatus.OK, {"tasks": items})
            return

        if method == "POST" and path == "/api/tasks":
            prompt = str(body.get("prompt", "")).strip()
            if not prompt:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"error": "Missing 'prompt'"}
                )
                return
            task = await self.start_task(
                prompt=prompt,
                agent=body.get("agent"),
                mode=str(body.get("mode", "auto")),
                effort=str(body.get("effort", "high")),
                cwd=body.get("cwd"),
                conversation_id=body.get("conversation_id"),
            )
            await self._send_http_json(writer, HTTPStatus.CREATED, {"task": task.to_dict(include_events=True)})
            return

        if path.startswith("/api/tasks/"):
            rest = path[len("/api/tasks/") :]
            if rest.endswith("/cancel") and method == "POST":
                task_id = rest[: -len("/cancel")].strip("/")
                task = await self.cancel_task(task_id)
                if not task:
                    await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": "Task not found"})
                    return
                await self._send_http_json(writer, HTTPStatus.OK, {"task": task.to_dict()})
                return

            if method == "GET" and "/" not in rest:
                task = self.tasks.get(rest)
                if not task:
                    await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": "Task not found"})
                    return
                await self._send_http_json(writer, HTTPStatus.OK, {"task": task.to_dict(include_events=True)})
                return

        if method == "POST" and path == "/api/agent/default":
            agent = str(body.get("agent", "")).strip()
            if not agent:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"error": "Missing 'agent'"}
                )
                return
            agent_file = Path.home() / ".config" / "omarchy" / "defaults" / "agent"
            agent_file.parent.mkdir(parents=True, exist_ok=True)
            agent_file.write_text(agent + "\n", encoding="utf-8")
            await self.broadcast("agent.default_changed", {"default_agent": agent})
            await self._send_http_json(writer, HTTPStatus.OK, {"ok": True, "default_agent": agent})
            return

        await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": "Not found"})

    async def _handle_websocket(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        headers: dict[str, str],
    ) -> None:
        ws_key = headers.get("sec-websocket-key", "")
        if not ws_key:
            await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Missing WebSocket key"})
            return
        accept = base64.b64encode(
            hashlib.sha1((ws_key + WS_GUID).encode("ascii")).digest()
        ).decode("ascii")
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        )
        writer.write(response.encode("ascii"))
        await writer.drain()

        client = WebSocketClient(reader, writer)
        self.ws_clients.add(client)
        try:
            await client.send_json({
                "type": "hello",
                "ts": utc_now_iso(),
                "data": {
                    "status": self.status_payload(),
                    "tasks": [self.tasks[tid].to_dict() for tid in self.task_order[:25]],
                },
            })
            while not client.closed:
                frame = await client.read_frame()
                if frame is None:
                    break
                opcode, payload = frame
                if opcode == 0x8:  # Close
                    break
                if opcode == 0x9:  # Ping
                    await client.send_frame(0xA, payload)
                elif opcode == 0x1:  # Text
                    try:
                        msg = json.loads(payload.decode("utf-8"))
                        if isinstance(msg, dict) and msg.get("type") == "ping":
                            await client.send_json({"type": "pong", "ts": utc_now_iso()})
                    except Exception:
                        pass
        finally:
            self.ws_clients.discard(client)
            await client.close()

    async def _send_http_json(
        self, writer: asyncio.StreamWriter, status: HTTPStatus, payload: dict[str, Any]
    ) -> None:
        body = json.dumps(payload).encode("utf-8")
        headers = (
            f"HTTP/1.1 {status.value} {status.phrase}\r\n"
            "Content-Type: application/json; charset=utf-8\r\n"
            f"Content-Length: {len(body)}\r\n"
            "Access-Control-Allow-Origin: *\r\n"
            "Connection: close\r\n\r\n"
        ).encode("ascii")
        try:
            writer.write(headers + body)
            await writer.drain()
        finally:
            writer.close()


def detect_lan_ips() -> list[str]:
    ips: list[str] = []
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        ips.append(sock.getsockname()[0])
        sock.close()
    except OSError:
        pass
    return ips or ["127.0.0.1"]


async def run_server(host: str, port: int, token: str | None) -> None:
    bridge = OmarchyWizardBridge(host=host, port=port, token=token)
    await bridge.start()
    ips = detect_lan_ips()
    print("✨ Omarchy Wizard Bridge is listening!")
    print(f"   Host/Port : {host}:{bridge.bound_port}")
    for ip in ips:
        print(f"   Pair URL  : http://{ip}:{bridge.bound_port}")
    print(f"   Token     : {bridge.token}")
    print(f"   Agent     : {get_default_agent()} (available: {', '.join(detect_available_agents())})")

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop_event.set)
    await stop_event.wait()
    await bridge.stop()


def main() -> None:
    parser = argparse.ArgumentParser(description="Omarchy Wizard Agent Bridge")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"Port (default: {DEFAULT_PORT})")
    parser.add_argument("--token", default=None, help="Explicit bearer token")
    args = parser.parse_args()
    asyncio.run(run_server(args.host, args.port, args.token))


if __name__ == "__main__":
    main()
