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
import ipaddress
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import ssl
import struct
import subprocess
import sys
import time
from typing import Any
from urllib.parse import parse_qs, quote, urlparse
import uuid

import omarchy_continuity
import omarchy_control
import omarchy_desktop
import omarchy_files
import omarchy_pty
import omarchy_sessions

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
DEFAULT_PORT = 7842
MAX_LOG_EVENTS = 500
MAX_TASKS = 100
MAX_HEADER_BYTES = 16 * 1024
MAX_JSON_BODY_BYTES = 256 * 1024
MAX_UPLOAD_BODY_BYTES = 35 * 1024 * 1024
MAX_WS_FRAME_BYTES = 2 * 1024 * 1024
AUTH_FAIL_WINDOW_SEC = 60.0
AUTH_FAIL_MAX = 8
MAX_TRACKED_PEERS = 1024
MIN_TOKEN_LEN = 24


def ensure_agent_paths() -> None:
    """Ensure mise shims and Omarchy bin directories are on PATH for systemd launches."""
    home = Path.home()
    extra = [
        str(home / ".local" / "share" / "mise" / "shims"),
        str(home / ".local" / "share" / "mise" / "command-wrappers" / "bin"),
        str(home / ".local" / "bin"),
        "/usr/share/omarchy/bin",
    ]
    current = os.environ.get("PATH", "").split(":")
    merged = [p for p in extra if Path(p).is_dir() and p not in current] + current
    os.environ["PATH"] = ":".join(p for p in merged if p)


ensure_agent_paths()


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def get_config_dir() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "omalink"


def _write_private_text(path: Path, content: str) -> None:
    """Create parent directory (0700) and write secret file atomically with mode 0600."""
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(path.parent, 0o700)
    except OSError:
        pass
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(str(path), flags, 0o600)
    try:
        os.write(fd, content.encode("utf-8"))
    finally:
        os.close(fd)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def _is_weak_token(token: str) -> bool:
    return len(token) < MIN_TOKEN_LEN or token.isdigit()


def generate_pairing_token() -> str:
    """Return a cryptographically random 256-bit URL-safe bearer token."""
    return secrets.token_urlsafe(32)


def load_or_create_token(explicit_token: str | None = None, *, rotate: bool = False) -> str:
    if explicit_token:
        return explicit_token.strip()
    env_token = (
        os.environ.get("OMALINK_TOKEN", "").strip()
        or os.environ.get("OMARCHY_WIZARD_TOKEN", "").strip()
    )
    if env_token:
        return env_token
    cfg_dir = get_config_dir()
    token_file = cfg_dir / "token"
    if not rotate and token_file.exists():
        saved = token_file.read_text(encoding="utf-8").strip()
        if saved and not _is_weak_token(saved):
            try:
                os.chmod(token_file, 0o600)
            except OSError:
                pass
            return saved
    # Migrate legacy token ONLY if it already meets strength requirements
    legacy_token_file = cfg_dir.parent / "omarchy-wizard" / "token"
    if not rotate and legacy_token_file.exists():
        legacy = legacy_token_file.read_text(encoding="utf-8").strip()
        if legacy and not _is_weak_token(legacy):
            _write_private_text(token_file, legacy + "\n")
            return legacy
    token = generate_pairing_token()
    _write_private_text(token_file, token + "\n")
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
            "--output-format",
            "stream-json",
        ]
        if mode == "auto":
            cmd.append("--dangerously-skip-permissions")
        if mode in {"auto", "accept-edits", "plan"}:
            cmd.extend(["--mode", mode])
        if effort in {"low", "medium", "high", "xhigh", "max"}:
            cmd.extend(["--effort", effort])
        if conversation_id:
            cmd.extend(["--conversation", conversation_id])
        cmd.extend(["-p", prompt])
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
        cmd = ["kimi"]
        if mode == "auto":
            cmd.append("--yolo")
        cmd.extend(["--output-format", "stream-json", "-p", prompt])
        return cmd

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
                else:
                    for nested_key in ("step_update", "result"):
                        nested_obj = payload.get(nested_key)
                        if isinstance(nested_obj, dict) and nested_obj.get("conversation_id"):
                            base["conversation_id"] = str(nested_obj["conversation_id"])
                            break

                # Extract readable text across common stream-json shapes
                text = _extract_readable_text(payload)
                if text:
                    base["text"] = text
                return base
        except json.JSONDecodeError:
            pass
    return base


def _extract_readable_text(payload: dict[str, Any]) -> str:
    step = payload.get("step_update")
    if isinstance(step, dict):
        delta = step.get("text_delta")
        if isinstance(delta, str) and delta.strip():
            return delta.strip()
        tool_name = step.get("tool_name")
        if tool_name:
            state = str(step.get("state") or "").lower()
            prefix = "Tool done" if state == "done" else "Using tool"
            return f"{prefix}: {tool_name}"
        step_type = step.get("step_type")
        state = step.get("state")
        if step_type and state:
            return f"{step_type} ({str(state).lower()})"

    init_obj = payload.get("init")
    if isinstance(init_obj, dict):
        cwd = init_obj.get("cwd")
        return f"Session initialized in {cwd}" if cwd else "Session initialized"

    for key in ("result", "message", "text", "content", "delta", "error"):
        val = payload.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
        if isinstance(val, dict):
            nested = val.get("response") or val.get("content") or val.get("text") or val.get("message")
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
        self.device_name: str = ""
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
        if length > MAX_WS_FRAME_BYTES:
            await self.close()
            return None
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

    def __init__(
        self,
        host: str = "0.0.0.0",
        port: int = DEFAULT_PORT,
        token: str | None = None,
        use_tls: bool = False,
    ) -> None:
        self.host = host
        self.port = port
        self.token = load_or_create_token(token)
        self.use_tls = bool(use_tls or os.environ.get("OMALINK_TLS", "").lower() in {"1", "true", "yes"} or os.environ.get("OMARCHY_WIZARD_TLS", "").lower() in {"1", "true", "yes"})
        self.tls_fingerprint: str = ""
        self._ssl_ctx: ssl.SSLContext | None = None
        self.tasks: dict[str, AgentTask] = {}
        self.task_order: list[str] = []
        self.ws_clients: set[WebSocketClient] = set()
        self._bg_tasks: set[asyncio.Task[None]] = set()
        self._theme_watch_task: asyncio.Task[None] | None = None
        self._mdns_proc: subprocess.Popen[bytes] | None = None
        self.server: asyncio.AbstractServer | None = None
        self.bound_port: int = port
        self._auth_failures: dict[str, list[float]] = {}

    @staticmethod
    def _normalize_peer_key(peer_ip: str) -> str:
        raw = peer_ip.strip()
        try:
            addr = ipaddress.ip_address(raw)
            if isinstance(addr, ipaddress.IPv6Address):
                if addr.ipv4_mapped:
                    return str(addr.ipv4_mapped)
                net = ipaddress.IPv6Network((addr, 64), strict=False)
                return f"{net.network_address}/64"
            return str(addr)
        except ValueError:
            return raw or "unknown"

    def _is_rate_limited(self, peer_ip: str) -> bool:
        key = self._normalize_peer_key(peer_ip)
        now = time.monotonic()
        stamps = [t for t in self._auth_failures.get(key, []) if (now - t) < AUTH_FAIL_WINDOW_SEC]
        if stamps:
            self._auth_failures[key] = stamps
        else:
            self._auth_failures.pop(key, None)
        return len(stamps) >= AUTH_FAIL_MAX

    def _record_auth_failure(self, peer_ip: str) -> None:
        key = self._normalize_peer_key(peer_ip)
        now = time.monotonic()
        if key not in self._auth_failures and len(self._auth_failures) >= MAX_TRACKED_PEERS:
            oldest_key = next(iter(self._auth_failures))
            self._auth_failures.pop(oldest_key, None)
        stamps = [t for t in self._auth_failures.get(key, []) if (now - t) < AUTH_FAIL_WINDOW_SEC]
        stamps.append(now)
        self._auth_failures[key] = stamps

    def _clear_auth_failures(self, peer_ip: str) -> None:
        key = self._normalize_peer_key(peer_ip)
        self._auth_failures.pop(key, None)

    def is_authorized(self, headers: dict[str, str], query: dict[str, list[str]] | None = None) -> bool:
        """Authenticate strictly via Authorization: Bearer <token> header (no URL query tokens)."""
        auth = headers.get("authorization", "")
        if auth.lower().startswith("bearer "):
            candidate = auth[7:].strip()
            if candidate and hmac.compare_digest(candidate, self.token):
                return True
        return False

    def pairing_uri(self) -> str:
        lan_ip = detect_lan_ips()[0]
        ts_ip = omarchy_control.detect_tailscale_ip()
        params = [
            f"host={quote(lan_ip)}",
            f"port={self.bound_port}",
            f"token={quote(self.token)}",
            f"tls={'1' if self.use_tls else '0'}",
        ]
        if self.tls_fingerprint:
            params.append(f"fp={quote(self.tls_fingerprint)}")
        if ts_ip:
            params.append(f"ts={quote(ts_ip)}")
        return f"omalink://pair?{'&'.join(params)}"

    def status_payload(self) -> dict[str, Any]:
        info = read_omarchy_info()
        running = sum(1 for t in self.tasks.values() if t.status == "running")
        ts_ip = omarchy_control.detect_tailscale_ip()
        return {
            "ok": True,
            "bridge_version": "2.0.0",
            "hostname": info["hostname"],
            "os_name": info["os_name"],
            "os_version": info["os_version"],
            "default_agent": get_default_agent(),
            "available_agents": detect_available_agents(),
            "workspaces": detect_workspaces(),
            "running_tasks": running,
            "connected_clients": len(self.ws_clients),
            "lan_ips": detect_lan_ips(),
            "tailscale_ip": ts_ip,
            "tls": self.use_tls,
            "tls_fingerprint": self.tls_fingerprint,
            "total_tasks": len(self.tasks),
            "theme": omarchy_control.read_theme_palette_sync(),
            "phone": omarchy_continuity.get_phone_device_state(),
            "replyable_notification": omarchy_continuity.latest_replyable_notification(),
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

    def _ensure_tls_context(self) -> ssl.SSLContext | None:
        if not self.use_tls:
            return None
        cfg = get_config_dir()
        cfg.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(cfg, 0o700)
        except OSError:
            pass
        cert_path = cfg / "cert.pem"
        key_path = cfg / "key.pem"
        if not (cert_path.is_file() and key_path.is_file()):
            if not shutil.which("openssl"):
                raise RuntimeError("openssl is required to generate self-signed TLS certificate")
            lan_ip = detect_lan_ips()[0]
            ts_ip = omarchy_control.detect_tailscale_ip()
            san = f"DNS:localhost,IP:127.0.0.1,IP:{lan_ip}" + (f",IP:{ts_ip}" if ts_ip else "")
            subprocess.run(
                [
                    "openssl",
                    "req",
                    "-x509",
                    "-newkey",
                    "ec",
                    "-pkeyopt",
                    "ec_paramgen_curve:prime256v1",
                    "-keyout",
                    str(key_path),
                    "-out",
                    str(cert_path),
                    "-days",
                    "825",
                    "-nodes",
                    "-subj",
                    f"/CN={socket.gethostname()}",
                    "-addext",
                    f"subjectAltName={san}",
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
                preexec_fn=lambda: os.umask(0o077),
            )
            os.chmod(key_path, 0o600)
            os.chmod(cert_path, 0o644)

        # Compute SHA-256 fingerprint of DER cert for client pinning
        pem_lines = [
            line.strip()
            for line in cert_path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.startswith("-----")
        ]
        der = base64.b64decode("".join(pem_lines))
        self.tls_fingerprint = hashlib.sha256(der).hexdigest()

        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(certfile=str(cert_path), keyfile=str(key_path))
        return ctx

    def _start_mdns(self) -> None:
        if self.port == 0 or os.environ.get("OMARCHY_WIZARD_NO_MDNS", "") == "1":
            return
        if not shutil.which("avahi-publish"):
            return
        try:
            lan_ip = detect_lan_ips()[0]
            ts_ip = omarchy_control.detect_tailscale_ip()
            svc_name = f"OmaLink ({socket.gethostname()})"
            cmd = [
                "avahi-publish",
                "-s",
                svc_name,
                "_omalink._tcp",
                str(self.bound_port),
                f"host={lan_ip}",
                f"tls={'1' if self.use_tls else '0'}",
            ]
            if self.tls_fingerprint:
                cmd.append(f"fp={self.tls_fingerprint}")
            if ts_ip:
                cmd.append(f"ts={ts_ip}")
            self._mdns_proc = subprocess.Popen(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            self._mdns_proc = None

    async def start(self) -> None:
        self._ssl_ctx = self._ensure_tls_context()
        self.server = await asyncio.start_server(
            self._handle_connection,
            self.host,
            self.port,
            ssl=self._ssl_ctx,
        )
        sockets = self.server.sockets
        if sockets:
            self.bound_port = sockets[0].getsockname()[1]
        self._start_mdns()
        self._theme_watch_task = asyncio.create_task(self._watch_host_loop())

    async def _watch_host_loop(self) -> None:
        last_sig = omarchy_control.read_theme_generation()
        last_clip_mtime = omarchy_continuity.clipboard_history_mtime()
        session_states: dict[str, tuple[str, int, str]] | None = None
        last_sessions_sig = ""
        tick = 0
        try:
            while True:
                await asyncio.sleep(2.0)
                tick += 1
                if not self.ws_clients:
                    continue
                sig = omarchy_control.read_theme_generation()
                if sig != last_sig and (sig[0] or sig[1]):
                    last_sig = sig
                    palette = await omarchy_control.read_theme_palette()
                    await self.broadcast("theme.changed", palette)

                clip_mtime = omarchy_continuity.clipboard_history_mtime()
                if clip_mtime > last_clip_mtime:
                    last_clip_mtime = clip_mtime
                    history = await asyncio.to_thread(omarchy_continuity.read_clipboard_history_sync, 15)
                    if history:
                        await self.broadcast(
                            "continuity.clipboard_update",
                            {"text": history[0], "history": history},
                        )

                # Poll live AI agent sessions every 4 seconds for real-time peek & alerts
                if tick % 2 == 0:
                    sessions = await asyncio.to_thread(omarchy_sessions.discover_sessions, 15)
                    cur_map = {
                        str(s["id"]): (
                            str(s.get("state", "idle")),
                            int(s.get("step_count", 0)),
                            str(s.get("last_activity", "")),
                        )
                        for s in sessions
                    }
                    cur_sig = json.dumps(cur_map, sort_keys=True)
                    if session_states is None:
                        session_states = cur_map
                        last_sessions_sig = cur_sig
                    else:
                        for s in sessions:
                            sid = str(s["id"])
                            cur_state = str(s.get("state", "idle"))
                            cur_steps = int(s.get("step_count", 0))
                            prev = session_states.get(sid)
                            prev_state = prev[0] if prev else ""
                            prev_steps = prev[1] if prev else -1
                            if cur_state == "needs_response" and (
                                prev_state != "needs_response" or cur_steps > prev_steps
                            ):
                                await self.broadcast("session.needs_response", {"session": s})
                            elif prev_state == "running" and cur_state == "idle":
                                await self.broadcast("session.completed", {"session": s})
                        if cur_sig != last_sessions_sig:
                            last_sessions_sig = cur_sig
                            await self.broadcast("sessions.updated", {"sessions": sessions})
                        session_states = cur_map
        except asyncio.CancelledError:
            return

    async def stop(self) -> None:
        if self._mdns_proc is not None and self._mdns_proc.poll() is None:
            try:
                self._mdns_proc.terminate()
                self._mdns_proc.wait(timeout=1.5)
            except Exception:
                try:
                    self._mdns_proc.kill()
                except Exception:
                    pass
            self._mdns_proc = None
        if self._theme_watch_task is not None and not self._theme_watch_task.done():
            self._theme_watch_task.cancel()
            try:
                await self._theme_watch_task
            except asyncio.CancelledError:
                pass
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
        peer = writer.get_extra_info("peername")
        peer_ip = str(peer[0]) if isinstance(peer, (tuple, list)) and peer else "unknown"
        try:
            raw_head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=10.0)
        except asyncio.LimitOverrunError:
            await self._send_http_json(
                writer, HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE, {"error": "Headers too large"}
            )
            return
        except Exception:
            writer.close()
            return

        if len(raw_head) > MAX_HEADER_BYTES:
            await self._send_http_json(
                writer, HTTPStatus.REQUEST_HEADER_FIELDS_TOO_LARGE, {"error": "Headers too large"}
            )
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

        # Unauthenticated health ping (never buffers any request body)
        if path == "/api/ping" and method == "GET":
            await self._send_http_json(
                writer, HTTPStatus.OK, {"ok": True, "app": "omalink-bridge", "tls": self.use_tls}
            )
            return

        # Enforce rate limiting & header-only authentication BEFORE buffering any body bytes!
        if self._is_rate_limited(peer_ip):
            await self._send_http_json(
                writer, HTTPStatus.TOO_MANY_REQUESTS, {"error": "Too many failed authentication attempts"}
            )
            return

        if not self.is_authorized(headers):
            self._record_auth_failure(peer_ip)
            await self._send_http_json(writer, HTTPStatus.UNAUTHORIZED, {"error": "Unauthorized"})
            return

        self._clear_auth_failures(peer_ip)

        # WebSocket upgrades on /ws, /ws/terminal, and /ws/desktop (already authenticated!)
        if method == "GET" and headers.get("upgrade", "").lower() == "websocket":
            if path in {"/ws", "/ws/terminal", "/ws/desktop"}:
                if path == "/ws/terminal" and not self.use_tls and peer_ip not in {"127.0.0.1", "::1"}:
                    await self._send_http_json(
                        writer,
                        HTTPStatus.FORBIDDEN,
                        {"error": "Remote terminal requires TLS encryption over non-loopback networks"},
                    )
                    return
                if path == "/ws":
                    await self._handle_websocket(reader, writer, headers)
                elif path == "/ws/terminal":
                    await self._handle_terminal_websocket(reader, writer, headers, query)
                else:
                    await self._handle_desktop_websocket(reader, writer, headers, query)
                return

        # Validate Content-Length and enforce strict per-route limits BEFORE buffering
        raw_cl = headers.get("content-length", "0").strip() or "0"
        try:
            content_length = int(raw_cl)
        except ValueError:
            await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Invalid Content-Length"})
            return
        if content_length < 0:
            await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Invalid Content-Length"})
            return

        max_body = MAX_UPLOAD_BODY_BYTES if path == "/api/files/upload" else MAX_JSON_BODY_BYTES
        if content_length > max_body:
            await self._send_http_json(
                writer, HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Request body too large"}
            )
            return

        body_bytes = b""
        if content_length > 0:
            try:
                body_bytes = await asyncio.wait_for(reader.readexactly(content_length), timeout=20.0)
            except Exception:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Incomplete request body"})
                return

        await self._route_http(writer, method, path, query, body_bytes)

    async def _route_http(
        self,
        writer: asyncio.StreamWriter,
        method: str,
        path: str,
        query: dict[str, list[str]],
        body_bytes: bytes,
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

        if method == "GET" and path == "/api/theme/current":
            raw_name = (query.get("name") or [None])[0]
            palette = await omarchy_control.read_theme_palette(raw_name)
            await self._send_http_json(writer, HTTPStatus.OK, palette)
            return

        if method == "GET" and path == "/api/system/state":
            state = await omarchy_control.read_system_state()
            await self._send_http_json(writer, HTTPStatus.OK, state)
            return

        if method == "POST" and path == "/api/system/action":
            action = str(body.get("action", "")).strip()
            params = body.get("params") if isinstance(body.get("params"), dict) else {}
            if not action:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"error": "Missing 'action'"}
                )
                return
            result = await omarchy_control.execute_control_action(action, params)
            status_code = HTTPStatus.OK if result.get("ok") else HTTPStatus.BAD_REQUEST
            if result.get("ok"):
                await self.broadcast("system.action", {"action": action, "message": result.get("message", "")})
                if action == "theme.set":
                    palette = await omarchy_control.read_theme_palette()
                    await self.broadcast("theme.changed", palette)
            await self._send_http_json(writer, status_code, result)
            return

        if method == "GET" and path == "/api/files/list":
            raw_path = (query.get("path") or [None])[0]
            show_hidden = ((query.get("hidden") or ["0"])[0]).lower() in {"1", "true", "yes"}
            try:
                listing = await omarchy_files.list_directory(raw_path, show_hidden=show_hidden)
                await self._send_http_json(writer, HTTPStatus.OK, listing)
            except FileNotFoundError as exc:
                await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": str(exc)})
            except PermissionError as exc:
                await self._send_http_json(writer, HTTPStatus.FORBIDDEN, {"error": str(exc)})
            return

        if method == "GET" and path == "/api/files/read":
            raw_path = (query.get("path") or [""])[0]
            if not raw_path:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Missing 'path'"})
                return
            try:
                preview = await omarchy_files.read_file_preview(raw_path)
                await self._send_http_json(writer, HTTPStatus.OK, preview)
            except FileNotFoundError as exc:
                await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": str(exc)})
            except PermissionError as exc:
                await self._send_http_json(writer, HTTPStatus.FORBIDDEN, {"error": str(exc)})
            return

        if method == "POST" and path == "/api/files/mkdir":
            parent_path = str(body.get("parent", "")).strip()
            name = str(body.get("name", "")).strip()
            try:
                res = await omarchy_files.create_directory(parent_path, name)
                await self._send_http_json(writer, HTTPStatus.CREATED, res)
            except FileNotFoundError as exc:
                await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": str(exc)})
            except (ValueError, FileExistsError, PermissionError) as exc:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if method == "POST" and path == "/api/files/rename":
            target_path = str(body.get("path", "")).strip()
            new_name = str(body.get("new_name", "")).strip()
            try:
                res = await omarchy_files.rename_entry(target_path, new_name)
                await self._send_http_json(writer, HTTPStatus.OK, res)
            except FileNotFoundError as exc:
                await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": str(exc)})
            except (ValueError, FileExistsError, PermissionError) as exc:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if method == "POST" and path == "/api/files/open":
            target_path = str(body.get("path", "")).strip()
            try:
                res = await omarchy_files.open_on_desktop(target_path)
                await self._send_http_json(writer, HTTPStatus.OK, res)
            except FileNotFoundError as exc:
                await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": str(exc)})
            return

        if method == "POST" and path == "/api/files/trash":
            target_path = str(body.get("path", "")).strip()
            try:
                res = await omarchy_files.trash_entry(target_path)
                await self._send_http_json(writer, HTTPStatus.OK, res)
            except FileNotFoundError as exc:
                await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": str(exc)})
            except (ValueError, RuntimeError, PermissionError) as exc:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if method == "POST" and path == "/api/files/upload":
            filename = str(body.get("filename", "")).strip() or "shared_file"
            raw_b64 = body.get("data_base64")
            dest_dir = str(body.get("dir", "")).strip() or None
            if not isinstance(raw_b64, str) or not raw_b64:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"error": "Missing 'data_base64'"}
                )
                return
            try:
                raw_bytes = base64.b64decode(raw_b64, validate=False)
                res = await omarchy_files.save_uploaded_file(filename, raw_bytes, dest_dir=dest_dir)
                await omarchy_continuity.notify_desktop(
                    title="File Received from Phone",
                    body=f"Saved {res['name']} ({res['size']} bytes)",
                    app_name="Continuity",
                    category="continuity",
                )
                await self.broadcast("files.uploaded", {"name": res["name"], "path": res["path"]})
                await self._send_http_json(writer, HTTPStatus.CREATED, res)
            except (ValueError, FileNotFoundError, PermissionError) as exc:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if method == "GET" and path == "/api/files/download":
            raw_path = (query.get("path") or [""])[0]
            if not raw_path:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Missing 'path'"})
                return
            try:
                fname, content = await omarchy_files.read_file_bytes(raw_path)
                await self._send_http_bytes(
                    writer,
                    HTTPStatus.OK,
                    content,
                    content_type="application/octet-stream",
                    filename=fname,
                )
            except FileNotFoundError as exc:
                await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": str(exc)})
            except (ValueError, PermissionError) as exc:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        if method == "GET" and path == "/api/agents/usage":
            force = ((query.get("force") or ["0"])[0]).lower() in {"1", "true"}
            agents = await omarchy_control.read_agents_usage(force=force)
            await self._send_http_json(writer, HTTPStatus.OK, {"agents": agents})
            return

        if method == "GET" and path == "/api/sessions":
            try:
                limit = int((query.get("limit") or ["20"])[0])
            except ValueError:
                limit = 20
            sessions = await asyncio.to_thread(omarchy_sessions.discover_sessions, limit)
            await self._send_http_json(writer, HTTPStatus.OK, {"ok": True, "sessions": sessions})
            return

        if path.startswith("/api/sessions/"):
            rest = path[len("/api/sessions/") :].strip("/")
            parts = rest.split("/")
            if len(parts) == 3 and parts[2] == "transcript" and method == "GET":
                agent_name, session_id = parts[0], parts[1]
                try:
                    limit = int((query.get("limit") or ["45"])[0])
                except ValueError:
                    limit = 45
                res = await asyncio.to_thread(
                    omarchy_sessions.read_session_transcript, agent_name, session_id, limit
                )
                status_code = HTTPStatus.OK if res.get("ok") else HTTPStatus.NOT_FOUND
                await self._send_http_json(writer, status_code, res)
                return

            if len(parts) == 3 and parts[2] == "send" and method == "POST":
                agent_name, session_id = parts[0], parts[1]
                try:
                    payload = json.loads(body_bytes.decode("utf-8")) if body_bytes else {}
                except json.JSONDecodeError:
                    await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Invalid JSON"})
                    return
                message = str(payload.get("message", "")).strip()
                if not message:
                    await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Message is required"})
                    return
                mode = str(payload.get("mode", "resume")).strip().lower()
                window_address = str(payload.get("window_address", "")).strip()
                workspace = str(payload.get("workspace", "")).strip() or None

                if mode == "terminal":
                    res = await asyncio.to_thread(
                        omarchy_sessions.send_to_live_terminal, window_address, message, True
                    )
                    status_code = HTTPStatus.OK if res.get("ok") else HTTPStatus.BAD_REQUEST
                    await self._send_http_json(writer, status_code, res)
                    return

                task = await self.start_task(
                    prompt=message,
                    agent=agent_name,
                    mode=str(payload.get("agent_mode", "auto")),
                    effort=str(payload.get("effort", "high")),
                    cwd=workspace,
                    conversation_id=session_id,
                )
                await self._send_http_json(
                    writer,
                    HTTPStatus.CREATED,
                    {"ok": True, "mode": "resume", "task": task.to_dict()},
                )
                return

            if len(parts) == 3 and parts[2] == "close" and method == "POST":
                agent_name, session_id = parts[0], parts[1]
                try:
                    payload = json.loads(body_bytes.decode("utf-8")) if body_bytes else {}
                except json.JSONDecodeError:
                    payload = {}
                step_count = int(payload.get("step_count", 0) or 0)
                # Cancel any running bridge-managed task for this conversation_id
                for t in list(self.tasks.values()):
                    if t.conversation_id == session_id and t.status == "running":
                        await self.cancel_task(t.id)
                res = await asyncio.to_thread(
                    omarchy_sessions.close_session,
                    agent_name,
                    session_id,
                    step_count,
                )
                if res.get("ok"):
                    sessions = await asyncio.to_thread(omarchy_sessions.discover_sessions, 20)
                    await self.broadcast("sessions.updated", {"sessions": sessions})
                status_code = HTTPStatus.OK if res.get("ok") else HTTPStatus.BAD_REQUEST
                await self._send_http_json(writer, status_code, res)
                return

        if method == "GET" and path == "/api/pairing/info":
            uri = self.pairing_uri()
            qr_b64 = ""
            if shutil.which("qrencode"):
                try:
                    proc = await asyncio.create_subprocess_exec(
                        "qrencode",
                        "-o",
                        "-",
                        "-s",
                        "6",
                        "-m",
                        "2",
                        stdin=asyncio.subprocess.PIPE,
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.DEVNULL,
                    )
                    out, _ = await asyncio.wait_for(
                        proc.communicate(input=uri.encode("utf-8")),
                        timeout=3.0,
                    )
                    if proc.returncode == 0 and out:
                        qr_b64 = base64.b64encode(out).decode("ascii")
                except Exception:
                    pass
            await self._send_http_json(
                writer,
                HTTPStatus.OK,
                {
                    "pair_uri": uri,
                    "lan_ips": detect_lan_ips(),
                    "tailscale_ip": omarchy_control.detect_tailscale_ip(),
                    "port": self.bound_port,
                    "tls": self.use_tls,
                    "tls_fingerprint": self.tls_fingerprint,
                    "qr_png_base64": qr_b64,
                },
            )
            return

        if method == "GET" and path == "/api/continuity/state":
            state = await omarchy_continuity.read_continuity_state()
            await self._send_http_json(writer, HTTPStatus.OK, state)
            return

        if method == "GET" and path == "/api/continuity/clipboard":
            res = await omarchy_continuity.get_clipboard()
            res["history"] = await asyncio.to_thread(omarchy_continuity.read_clipboard_history_sync, 20)
            await self._send_http_json(writer, HTTPStatus.OK, res)
            return

        if method == "POST" and path == "/api/continuity/clipboard":
            text = body.get("text")
            if not isinstance(text, str) or not text:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"error": "Missing non-empty 'text'"}
                )
                return
            res = await omarchy_continuity.set_clipboard(text, notify=bool(body.get("notify", True)))
            if res.get("ok"):
                await self.broadcast("continuity.clipboard", {"length": len(text), "preview": res["preview"]})
            await self._send_http_json(
                writer, HTTPStatus.OK if res.get("ok") else HTTPStatus.BAD_REQUEST, res
            )
            return

        if method == "POST" and path == "/api/continuity/push-clipboard":
            clip = await omarchy_continuity.get_clipboard()
            text = str(clip.get("text", ""))
            if not text:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"ok": False, "error": "Desktop clipboard is empty"}
                )
                return
            target_device = str(body.get("target_device", "")).strip()
            if not target_device:
                await self._send_http_json(
                    writer,
                    HTTPStatus.CONFLICT,
                    {
                        "ok": False,
                        "error": "Clipboard delivery requires an identified target device",
                    },
                )
                return
            active_clients = [c for c in list(self.ws_clients) if not c.closed]
            matched = [
                c for c in active_clients
                if c.device_name and c.device_name == target_device
            ]
            if len(matched) != 1:
                await self._send_http_json(
                    writer,
                    HTTPStatus.CONFLICT,
                    {
                        "ok": False,
                        "error": "Clipboard delivery requires a single connected client matching the displayed device",
                    },
                )
                return
            recipient = matched[0]

            history = await asyncio.to_thread(omarchy_continuity.read_clipboard_history_sync, 15)
            await recipient.send_json({
                "type": "continuity.clipboard_update",
                "ts": utc_now_iso(),
                "data": {"text": text, "history": history},
            })
            await self._send_http_json(
                writer,
                HTTPStatus.OK,
                {"ok": True, "length": len(text), "target_device": recipient.device_name},
            )
            return

        if method == "POST" and path == "/api/continuity/notify":
            title = str(body.get("title", "")).strip()
            msg_body = str(body.get("body", "")).strip()
            caller = str(body.get("caller", "")).strip()
            if not title and not caller and not msg_body:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"error": "Missing notification title/caller/body"}
                )
                return
            entry = await omarchy_continuity.notify_desktop(
                title=title,
                body=msg_body,
                app_name=str(body.get("app_name", "Phone")),
                package_name=str(body.get("package_name", "")),
                category=str(body.get("category", "notification")),
                urgency=str(body.get("urgency", "normal")),
                caller=caller,
                can_reply=bool(body.get("can_reply", False)),
                reply_id=str(body.get("reply_id", "")),
            )
            await self.broadcast("continuity.notify", entry)
            await self._send_http_json(writer, HTTPStatus.OK, {"ok": True, "entry": entry})
            return

        if method == "POST" and path == "/api/continuity/reply":
            reply_id = str(body.get("reply_id", "")).strip()
            text = str(body.get("text", "")).strip()
            if not reply_id or not text:
                await self._send_http_json(
                    writer, HTTPStatus.BAD_REQUEST, {"error": "Missing 'reply_id' or 'text'"}
                )
                return
            await self.broadcast("phone.reply", {"reply_id": reply_id, "text": text})
            await self._send_http_json(
                writer,
                HTTPStatus.OK,
                {"ok": True, "reply_id": reply_id, "delivered_clients": len(self.ws_clients)},
            )
            return

        if method == "POST" and path == "/api/continuity/device":
            battery_raw = body.get("battery")
            battery = int(battery_raw) if isinstance(battery_raw, (int, float)) else None
            phone = omarchy_continuity.update_phone_device_state(
                name=str(body.get("name", "")),
                battery=battery,
                charging=bool(body.get("charging", False)),
            )
            await self.broadcast("continuity.device", phone)
            await self._send_http_json(writer, HTTPStatus.OK, {"ok": True, "phone": phone})
            return

        if method == "POST" and path == "/api/continuity/ring":
            duration = max(3, min(30, int(body.get("duration", 12))))
            await self.broadcast("phone.ring", {"duration": duration})
            await self._send_http_json(
                writer,
                HTTPStatus.OK,
                {"ok": True, "duration": duration, "delivered_clients": len(self.ws_clients)},
            )
            return

        if method == "POST" and path == "/api/continuity/handoff":
            res = await omarchy_continuity.handoff_to_desktop(
                url=str(body.get("url", "")),
                text=str(body.get("text", "")),
                subject=str(body.get("subject", "")),
                app=str(body.get("app", "")),
                package_name=str(body.get("package_name", "")),
                copy_to_clipboard=bool(body.get("copy_to_clipboard", True)),
            )
            if not res.get("ok") and "error" in res:
                await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, res)
                return
            await self.broadcast("continuity.handoff", res)
            await self._send_http_json(
                writer, HTTPStatus.OK if res.get("ok") else HTTPStatus.BAD_REQUEST, res
            )
            return

        await self._send_http_json(writer, HTTPStatus.NOT_FOUND, {"error": "Not found"})

    async def _upgrade_websocket(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        headers: dict[str, str],
    ) -> WebSocketClient | None:
        ws_key = headers.get("sec-websocket-key", "")
        if not ws_key:
            await self._send_http_json(writer, HTTPStatus.BAD_REQUEST, {"error": "Missing WebSocket key"})
            return None
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
        return WebSocketClient(reader, writer)

    async def _handle_terminal_websocket(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        headers: dict[str, str],
        query: dict[str, list[str]],
    ) -> None:
        client = await self._upgrade_websocket(reader, writer, headers)
        if client is None:
            return
        await omarchy_pty.handle_terminal_websocket(client, query)

    async def _handle_desktop_websocket(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        headers: dict[str, str],
        query: dict[str, list[str]],
    ) -> None:
        client = await self._upgrade_websocket(reader, writer, headers)
        if client is None:
            return
        await omarchy_desktop.handle_desktop_websocket(client, query)

    async def _handle_websocket(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        headers: dict[str, str],
    ) -> None:
        client = await self._upgrade_websocket(reader, writer, headers)
        if client is None:
            return
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
                        if isinstance(msg, dict):
                            mtype = msg.get("type")
                            if mtype == "ping":
                                await client.send_json({"type": "pong", "ts": utc_now_iso()})
                            elif mtype == "device.status":
                                raw_bat = msg.get("battery")
                                dev_name = str(msg.get("name", "")).strip()[:48]
                                if dev_name:
                                    client.device_name = dev_name
                                omarchy_continuity.update_phone_device_state(
                                    name=dev_name,
                                    battery=int(raw_bat) if isinstance(raw_bat, (int, float)) else None,
                                    charging=bool(msg.get("charging", False)),
                                )
                    except Exception:
                        pass
        finally:
            self.ws_clients.discard(client)
            await client.close()

    async def _send_http_bytes(
        self,
        writer: asyncio.StreamWriter,
        status: HTTPStatus,
        body: bytes,
        *,
        content_type: str = "application/octet-stream",
        filename: str | None = None,
    ) -> None:
        safe_fn = ""
        if filename:
            safe_fn = "".join(
                ch for ch in filename if ch >= " " and ch not in {'"', "\\", "/", "\r", "\n"}
            ).strip()
        disp = f'Content-Disposition: attachment; filename="{safe_fn}"\r\n' if safe_fn else ""
        headers = (
            f"HTTP/1.1 {status.value} {status.phrase}\r\n"
            f"Content-Type: {content_type}\r\n"
            f"{disp}"
            f"Content-Length: {len(body)}\r\n"
            "Connection: close\r\n\r\n"
        ).encode("utf-8")
        try:
            writer.write(headers + body)
            await writer.drain()
        finally:
            writer.close()

    async def _send_http_json(
        self, writer: asyncio.StreamWriter, status: HTTPStatus, payload: dict[str, Any]
    ) -> None:
        body = json.dumps(payload).encode("utf-8")
        headers = (
            f"HTTP/1.1 {status.value} {status.phrase}\r\n"
            "Content-Type: application/json; charset=utf-8\r\n"
            f"Content-Length: {len(body)}\r\n"
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


async def run_server(
    host: str,
    port: int,
    token: str | None,
    use_tls: bool = True,
    rotate_token: bool = False,
) -> None:
    if rotate_token and not token:
        token = load_or_create_token(rotate=True)
    bridge = OmarchyWizardBridge(host=host, port=port, token=token, use_tls=use_tls)
    await bridge.start()
    ips = detect_lan_ips()
    scheme = "https" if bridge.use_tls else "http"
    print("✨ OmaLink Bridge v3.4 is listening!")
    print(f"   Host/Port : {host}:{bridge.bound_port} ({'TLS' if bridge.use_tls else 'INSECURE HTTP'})")
    for ip in ips:
        print(f"   Pair URL  : {scheme}://{ip}:{bridge.bound_port}")
    if bridge.tls_fingerprint:
        print(f"   TLS SHA256: {bridge.tls_fingerprint}")
    print(f"   Token File: {get_config_dir() / 'token'} (redacted from logs)")
    print(f"   Agent     : {get_default_agent()} (available: {', '.join(detect_available_agents())})")

    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop_event.set)
    await stop_event.wait()
    await bridge.stop()


def main() -> None:
    parser = argparse.ArgumentParser(description="OmaLink Companion & AI Agent Bridge")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"Port (default: {DEFAULT_PORT})")
    parser.add_argument("--token", default=None, help="Explicit bearer token")
    parser.add_argument("--tls", action="store_true", help="Enable self-signed TLS encryption (default for non-loopback)")
    parser.add_argument(
        "--insecure-http",
        action="store_true",
        help="Disable TLS and serve plaintext HTTP (not recommended outside localhost)",
    )
    parser.add_argument("--rotate-token", action="store_true", help="Generate a fresh 256-bit bearer token on startup")
    args = parser.parse_args()
    is_loopback = args.host in {"127.0.0.1", "::1", "localhost"}
    use_tls = (not args.insecure_http) and (args.tls or not is_loopback)
    asyncio.run(
        run_server(
            args.host,
            args.port,
            args.token,
            use_tls=use_tls,
            rotate_token=args.rotate_token,
        )
    )


if __name__ == "__main__":
    main()
