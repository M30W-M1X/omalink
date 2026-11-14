#!/usr/bin/env python3
"""Pure-stdlib async PTY session manager for interactive remote shells."""

from __future__ import annotations

import asyncio
import codecs
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import shutil
import signal
import struct
import subprocess
import termios
from typing import Any


def clamp_terminal_size(cols: Any, rows: Any) -> tuple[int, int]:
    """Clamp terminal dimensions to sane bounds."""
    try:
        c = int(cols)
    except (TypeError, ValueError):
        c = 80
    try:
        r = int(rows)
    except (TypeError, ValueError):
        r = 24
    return max(20, min(c, 400)), max(5, min(r, 200))


def _resolve_shell() -> list[str]:
    shell = os.environ.get("SHELL", "").strip()
    if not shell or not Path(shell).exists():
        shell = shutil.which("bash") or shutil.which("zsh") or shutil.which("sh") or "/bin/sh"
    name = Path(shell).name
    if name in {"bash", "zsh", "fish", "sh"}:
        return [shell, "-l"]
    return [shell]


def _resolve_cwd(raw_cwd: str | None) -> Path:
    if raw_cwd:
        try:
            candidate = Path(raw_cwd).expanduser().resolve()
            if candidate.is_dir():
                return candidate
        except OSError:
            pass
    return Path.home()


class PtySession:
    """Manages an interactive pseudo-terminal child process bridged to asyncio."""

    def __init__(
        self,
        loop: asyncio.AbstractEventLoop,
        cwd: str | None = None,
        cols: int = 80,
        rows: int = 24,
        shell_cmd: list[str] | None = None,
    ) -> None:
        self.loop = loop
        self.cwd = _resolve_cwd(cwd)
        self.cols, self.rows = clamp_terminal_size(cols, rows)
        self.shell_cmd = shell_cmd or _resolve_shell()
        self.master_fd: int | None = None
        self.proc: subprocess.Popen[bytes] | None = None
        self.events: asyncio.Queue[tuple[str, Any] | None] = asyncio.Queue()
        self._decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        self._reader_active = False
        self._closed = False
        self._exit_sent = False
        self._wait_task: asyncio.Task[None] | None = None

    def start(self) -> None:
        """Spawn the shell attached to a fresh PTY."""
        master_fd, slave_fd = pty.openpty()
        try:
            winsize = struct.pack("HHHH", self.rows, self.cols, 0, 0)
            fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            env.setdefault("COLORTERM", "truecolor")

            def _setup_ctty() -> None:
                # Child is session leader via start_new_session=True; claim controlling tty.
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)

            self.proc = subprocess.Popen(
                self.shell_cmd,
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                cwd=str(self.cwd),
                env=env,
                start_new_session=True,
                close_fds=True,
                preexec_fn=_setup_ctty,
            )
        except Exception:
            os.close(master_fd)
            os.close(slave_fd)
            raise

        os.close(slave_fd)
        os.set_blocking(master_fd, False)
        self.master_fd = master_fd
        self.loop.add_reader(master_fd, self._on_master_readable)
        self._reader_active = True
        self._wait_task = self.loop.create_task(self._watch_exit())

    def _on_master_readable(self) -> None:
        if self.master_fd is None or self._closed:
            return
        chunks: list[bytes] = []
        eof = False
        while True:
            try:
                data = os.read(self.master_fd, 65536)
                if not data:
                    eof = True
                    break
                chunks.append(data)
            except BlockingIOError:
                break
            except OSError as exc:
                if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                    break
                eof = True
                break

        if chunks:
            text = self._decoder.decode(b"".join(chunks), final=False)
            if text:
                self.events.put_nowait(("output", text))

        if eof:
            tail = self._decoder.decode(b"", final=True)
            if tail:
                self.events.put_nowait(("output", tail))
            self._stop_reader()
            self._emit_exit_if_ready()

    def _stop_reader(self) -> None:
        if self._reader_active and self.master_fd is not None:
            try:
                self.loop.remove_reader(self.master_fd)
            except Exception:
                pass
            self._reader_active = False

    async def _watch_exit(self) -> None:
        if self.proc is None:
            return
        code = await asyncio.to_thread(self.proc.wait)
        # Allow any buffered PTY bytes already readable to flush before emitting exit.
        await asyncio.sleep(0.03)
        if not self._closed:
            self._on_master_readable()
            self._emit_exit_if_ready(code)

    def _emit_exit_if_ready(self, forced_code: int | None = None) -> None:
        if self._exit_sent:
            return
        code = forced_code
        if code is None and self.proc is not None:
            code = self.proc.poll()
        if code is None:
            return
        self._exit_sent = True
        self.events.put_nowait(("exit", code))

    def write_input(self, text: str) -> None:
        """Write UTF-8 input bytes to the PTY master."""
        if self.master_fd is None or self._closed or not text:
            return
        data = text.encode("utf-8", errors="replace")
        view = memoryview(data)
        offset = 0
        while offset < len(data):
            try:
                written = os.write(self.master_fd, view[offset:])
                if written <= 0:
                    break
                offset += written
            except BlockingIOError:
                # Non-blocking PTY buffer temporarily full; yield briefly would require async,
                # drop only on hard failure after small spin in emergency.
                break
            except OSError:
                break

    def resize(self, cols: Any, rows: Any) -> tuple[int, int]:
        """Resize the PTY window and notify the child process group."""
        self.cols, self.rows = clamp_terminal_size(cols, rows)
        if self.master_fd is not None and not self._closed:
            try:
                winsize = struct.pack("HHHH", self.rows, self.cols, 0, 0)
                fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, winsize)
                if self.proc is not None and self.proc.poll() is None:
                    os.killpg(self.proc.pid, signal.SIGWINCH)
            except OSError:
                pass
        return self.cols, self.rows

    async def close(self) -> None:
        """Terminate child shell and release PTY descriptors."""
        if self._closed:
            return
        self._closed = True
        self._stop_reader()

        if self.proc is not None and self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGHUP)
            except OSError:
                pass
            try:
                await asyncio.wait_for(asyncio.to_thread(self.proc.wait), timeout=1.0)
            except asyncio.TimeoutError:
                try:
                    os.killpg(self.proc.pid, signal.SIGKILL)
                    await asyncio.to_thread(self.proc.wait)
                except OSError:
                    pass

        if self._wait_task is not None and not self._wait_task.done():
            self._wait_task.cancel()
            try:
                await self._wait_task
            except asyncio.CancelledError:
                pass

        if self.master_fd is not None:
            try:
                os.close(self.master_fd)
            except OSError:
                pass
            self.master_fd = None

        self.events.put_nowait(None)


async def handle_terminal_websocket(
    ws: Any,
    query: dict[str, list[str]],
    shell_cmd: list[str] | None = None,
) -> None:
    """Bridge an authenticated WebSocketClient to a fresh interactive PtySession."""
    loop = asyncio.get_running_loop()
    raw_cols = (query.get("cols") or ["80"])[0]
    raw_rows = (query.get("rows") or ["24"])[0]
    raw_cwd = (query.get("cwd") or [""])[0] or None
    cols, rows = clamp_terminal_size(raw_cols, raw_rows)

    session = PtySession(
        loop=loop,
        cwd=raw_cwd,
        cols=cols,
        rows=rows,
        shell_cmd=shell_cmd,
    )
    try:
        session.start()
    except OSError as exc:
        await ws.send_json({"type": "error", "message": f"Failed to spawn shell: {exc}"})
        await ws.close()
        return

    await ws.send_json({
        "type": "ready",
        "cwd": str(session.cwd),
        "cols": session.cols,
        "rows": session.rows,
        "shell": session.shell_cmd[0],
        "pid": session.proc.pid if session.proc else None,
    })

    async def _pump_pty_to_ws() -> None:
        while not ws.closed:
            item = await session.events.get()
            if item is None:
                break
            kind, payload = item
            if kind == "output":
                await ws.send_json({"type": "output", "data": payload})
            elif kind == "exit":
                await ws.send_json({"type": "exit", "code": payload})
                break

    async def _pump_ws_to_pty() -> None:
        while not ws.closed:
            frame = await ws.read_frame()
            if frame is None:
                break
            opcode, payload = frame
            if opcode == 0x8:  # Close
                break
            if opcode == 0x9:  # Ping
                await ws.send_frame(0xA, payload)
                continue
            if opcode != 0x1:  # Text JSON frames expected
                continue
            try:
                msg = json.loads(payload.decode("utf-8"))
            except Exception:
                continue
            if not isinstance(msg, dict):
                continue
            msg_type = msg.get("type")
            if msg_type == "input":
                data = msg.get("data")
                if isinstance(data, str):
                    session.write_input(data)
            elif msg_type == "resize":
                session.resize(msg.get("cols"), msg.get("rows"))
            elif msg_type == "ping":
                await ws.send_json({"type": "pong"})

    pump_out = asyncio.create_task(_pump_pty_to_ws())
    pump_in = asyncio.create_task(_pump_ws_to_pty())
    try:
        done, pending = await asyncio.wait(
            {pump_out, pump_in},
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
        await session.close()
        await ws.close()
