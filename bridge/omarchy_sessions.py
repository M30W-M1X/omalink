"""Live AI Agent session discovery, transcript peeking, and interactive reply helpers for OmaLink."""

from __future__ import annotations

from datetime import datetime, timezone
import glob
import json
import os
from pathlib import Path
import shutil
import signal
import sqlite3
import subprocess
import time
from typing import Any
from urllib.parse import unquote, urlparse


def _parse_workspace_uri(raw_uris: str) -> str:
    """Extract a clean local filesystem path from agy's workspace_uris JSON column."""
    if not raw_uris:
        return ""
    try:
        parsed = json.loads(raw_uris)
        if isinstance(parsed, list) and parsed:
            first = str(parsed[0])
            if first.startswith("file://"):
                return unquote(urlparse(first).path)
            return first
    except Exception:
        pass
    return ""


def _read_tail_lines(path: Path, max_bytes: int = 65536) -> list[str]:
    """Read the last `max_bytes` of a UTF-8 JSONL file as complete lines."""
    if not path.exists():
        return []
    try:
        size = path.stat().st_size
        with path.open("rb") as fh:
            if size > max_bytes:
                fh.seek(size - max_bytes)
                raw = fh.read()
                nl = raw.find(b"\n")
                if nl != -1:
                    raw = raw[nl + 1 :]
            else:
                raw = fh.read()
        return [ln for ln in raw.decode("utf-8", errors="replace").splitlines() if ln.strip()]
    except OSError:
        return []


def _get_hyprland_clients() -> list[dict[str, Any]]:
    if not shutil.which("hyprctl"):
        return []
    try:
        proc = subprocess.run(
            ["hyprctl", "clients", "-j"],
            capture_output=True,
            text=True,
            timeout=1.2,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            data = json.loads(proc.stdout)
            if isinstance(data, list):
                return data
    except Exception:
        pass
    return []


def _read_proc_ppid(pid: int) -> int:
    try:
        stat_txt = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8", errors="replace")
        rparen = stat_txt.rfind(")")
        if rparen != -1:
            parts = stat_txt[rparen + 2 :].split()
            if len(parts) >= 2:
                return int(parts[1])
    except Exception:
        pass
    return 0


def _find_window_for_pid(pid: int, clients_by_pid: dict[int, dict[str, Any]]) -> dict[str, Any] | None:
    cur = pid
    for _ in range(8):
        if cur <= 1:
            break
        if cur in clients_by_pid:
            return clients_by_pid[cur]
        cur = _read_proc_ppid(cur)
    return None


def _scan_open_agy_processes() -> dict[str, dict[str, Any]]:
    """Inspect user-owned running `agy` processes via /proc to find open session locks."""
    open_sessions: dict[str, dict[str, Any]] = {}
    clients = _get_hyprland_clients()
    clients_by_pid: dict[int, dict[str, Any]] = {}
    for c in clients:
        if isinstance(c, dict) and isinstance(c.get("pid"), int):
            clients_by_pid[c["pid"]] = c

    for fd_dir in glob.glob("/proc/[0-9]*/fd"):
        pid_str = fd_dir.split("/")[2]
        try:
            pid = int(pid_str)
            cmd = (
                Path(f"/proc/{pid}/cmdline")
                .read_bytes()
                .decode("utf-8", errors="replace")
                .replace("\x00", " ")
                .strip()
            )
        except OSError:
            continue
        if "agy" not in cmd:
            continue
        # Skip non-agent shells/wrappers that merely mention agy in an unrelated script
        first_tok = os.path.basename(cmd.split()[0]) if cmd.split() else ""
        if first_tok not in ("agy",) and "/antigravity-cli/" not in cmd:
            continue

        conv_ids: set[str] = set()
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if "antigravity-cli/presence/" in target and target.endswith(".lock"):
                    conv_ids.add(os.path.basename(target)[:-5])
        except OSError:
            continue

        if not conv_ids:
            continue

        win = _find_window_for_pid(pid, clients_by_pid)
        for cid in conv_ids:
            open_sessions[cid] = {
                "pid": pid,
                "window_address": str(win.get("address", "")) if win else "",
                "window_title": str(win.get("title", "")) if win else "",
                "workspace_id": (
                    win.get("workspace", {}).get("id")
                    if isinstance(win, dict) and isinstance(win.get("workspace"), dict)
                    else None
                ),
            }
    return open_sessions


def _parse_ask_question_args(args: Any) -> list[dict[str, Any]]:
    if not isinstance(args, dict):
        return []
    raw_q = args.get("questions")
    if isinstance(raw_q, str):
        try:
            raw_q = json.loads(raw_q)
        except Exception:
            return []
    if not isinstance(raw_q, list):
        return []
    out: list[dict[str, Any]] = []
    for item in raw_q:
        if not isinstance(item, dict):
            continue
        q_text = str(item.get("question", "")).strip()
        opts = [str(o).strip() for o in (item.get("options") or []) if str(o).strip()]
        if q_text:
            out.append(
                {
                    "question": q_text,
                    "options": opts[:8],
                    "is_multi_select": bool(item.get("is_multi_select", False)),
                }
            )
    return out


def _summarize_tool_call(tc: dict[str, Any]) -> str:
    name = str(tc.get("name", "tool"))
    args = tc.get("args") if isinstance(tc.get("args"), dict) else {}
    if name == "run_command":
        summary = str(args.get("toolSummary") or args.get("CommandLine") or "").strip().strip('"')
        return f"Running: {summary[:100]}" if summary else "Running command"
    if name in ("edit_file", "write_file", "read_file"):
        p = str(args.get("Path") or "").strip().strip('"')
        verb = {"edit_file": "Editing", "write_file": "Writing", "read_file": "Reading"}[name]
        return f"{verb}: {os.path.basename(p) or p}" if p else f"{verb} file"
    if name == "ask_question":
        qs = _parse_ask_question_args(args)
        if qs:
            return f"Question: {qs[0]['question'][:120]}"
        return "Waiting for your answer"
    if name == "search_web":
        q = str(args.get("query") or "").strip().strip('"')
        return f"Searching web: {q[:90]}" if q else "Searching web"
    return f"Tool: {name}"


def _inspect_agy_transcript_tail(
    transcript_path: Path,
    db_status: str,
    not_fully_idle: bool,
) -> dict[str, Any]:
    """Analyze the tail of an agy transcript.jsonl to infer state, activity, and pending question."""
    lines = _read_tail_lines(transcript_path, max_bytes=49152)
    last_activity = ""
    pending_questions: list[dict[str, Any]] = []
    last_role = ""
    last_step_type = ""
    last_tool_name = ""
    last_step_status = ""
    last_created_at = ""
    last_assistant_text = ""

    parsed_steps: list[dict[str, Any]] = []
    for ln in lines[-30:]:
        try:
            obj = json.loads(ln)
            if isinstance(obj, dict):
                parsed_steps.append(obj)
        except Exception:
            continue

    for step in parsed_steps:
        stype = str(step.get("type", ""))
        src = str(step.get("source", ""))
        content = str(step.get("content", "") or "").strip()
        tool_calls = step.get("tool_calls") if isinstance(step.get("tool_calls"), list) else []
        last_step_type = stype
        last_step_status = str(step.get("status", ""))
        if step.get("created_at"):
            last_created_at = str(step["created_at"])

        if stype == "USER_INPUT" or src == "USER_EXPLICIT":
            last_role = "user"
            last_tool_name = ""
            pending_questions = []
            if content:
                last_activity = f"You: {content[:120]}"
        elif stype == "PLANNER_RESPONSE":
            last_role = "assistant"
            if tool_calls:
                last_tc = tool_calls[-1] if isinstance(tool_calls[-1], dict) else {}
                last_tool_name = str(last_tc.get("name", ""))
                last_activity = _summarize_tool_call(last_tc)
                if last_tool_name == "ask_question":
                    pending_questions = _parse_ask_question_args(last_tc.get("args"))
                else:
                    pending_questions = []
            elif content:
                last_tool_name = ""
                pending_questions = []
                last_assistant_text = content
                first_line = next((l.strip() for l in content.splitlines() if l.strip()), content)
                last_activity = first_line[:140]
        elif stype == "GENERIC" and src == "MODEL":
            # Tool output returned -> clears prior ask_question if answered
            if last_tool_name == "ask_question":
                pending_questions = []
                last_tool_name = ""

    # Determine normalized state
    upper_db = db_status.upper()
    if pending_questions or "WAITING" in upper_db:
        state = "needs_response"
    elif "ERROR" in upper_db or last_step_status == "ERROR":
        state = "error"
    elif "RUNNING" in upper_db or not_fully_idle:
        state = "running"
    elif last_role == "assistant" and not last_tool_name and last_assistant_text.rstrip().endswith("?"):
        state = "needs_response"
    else:
        state = "idle"

    return {
        "state": state,
        "last_activity": last_activity,
        "pending_questions": pending_questions,
        "last_step_type": last_step_type,
        "last_created_at": last_created_at,
    }


def _discover_agy_sessions(limit: int = 20, agy_root: Path | None = None) -> list[dict[str, Any]]:
    root = agy_root or (Path.home() / ".gemini" / "antigravity-cli")
    db_path = root / "conversation_summaries.db"
    if not db_path.exists():
        return []

    open_map = _scan_open_agy_processes() if agy_root is None else {}
    rows: list[tuple[Any, ...]] = []
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=0.5)
        try:
            rows = conn.execute(
                """
                SELECT conversation_id, title, preview, step_count, last_modified_time,
                       workspace_uris, status, not_fully_idle
                FROM conversation_summaries
                WHERE COALESCE(parent_conversation_id, '') = ''
                  AND COALESCE(killed, 0) = 0
                ORDER BY last_modified_time DESC
                LIMIT ?
                """,
                (max(1, min(limit, 50)),),
            ).fetchall()
        finally:
            conn.close()
    except Exception:
        return []

    sessions: list[dict[str, Any]] = []
    for row in rows:
        cid, title, preview, step_count, modified, ws_uris, status, not_idle = row
        cid = str(cid or "")
        if not cid:
            continue
        workspace = _parse_workspace_uri(str(ws_uris or ""))
        transcript_path = root / "brain" / cid / ".system_generated" / "logs" / "transcript.jsonl"
        tail_info = _inspect_agy_transcript_tail(
            transcript_path,
            str(status or ""),
            bool(not_idle),
        )
        open_info = open_map.get(cid)
        clean_title = str(title or "").strip() or str(preview or "").strip()[:60] or f"Session {cid[:8]}"
        last_activity = tail_info["last_activity"] or str(preview or "").strip()[:140]

        sessions.append(
            {
                "id": cid,
                "agent": "agy",
                "title": clean_title,
                "workspace": workspace or str(Path.home()),
                "state": tail_info["state"],
                "raw_status": str(status or ""),
                "is_open": open_info is not None,
                "pid": open_info["pid"] if open_info else None,
                "window_address": open_info["window_address"] if open_info else "",
                "window_title": open_info["window_title"] if open_info else "",
                "step_count": int(step_count or 0),
                "updated_at": tail_info["last_created_at"] or str(modified or ""),
                "last_activity": last_activity,
                "pending_questions": tail_info["pending_questions"],
                "can_resume": True,
                "can_send_terminal": bool(open_info and open_info.get("window_address")),
            }
        )
    return sessions


def _discover_claude_sessions(limit: int = 8, claude_root: Path | None = None) -> list[dict[str, Any]]:
    root = claude_root or (Path.home() / ".claude" / "projects")
    if not root.exists():
        return []
    candidates: list[tuple[float, Path]] = []
    try:
        for p in root.rglob("*.jsonl"):
            if p.name.startswith("agent-"):
                continue
            try:
                candidates.append((p.stat().st_mtime, p))
            except OSError:
                continue
    except OSError:
        return []
    candidates.sort(key=lambda item: item[0], reverse=True)

    sessions: list[dict[str, Any]] = []
    now = time.time()
    for mtime, path in candidates[:limit]:
        lines = _read_tail_lines(path, max_bytes=24576)
        sid = path.stem
        cwd = str(Path.home())
        title = f"Claude {sid[:8]}"
        last_activity = ""
        last_role = ""
        for ln in lines[-20:]:
            try:
                obj = json.loads(ln)
            except Exception:
                continue
            if obj.get("cwd"):
                cwd = str(obj["cwd"])
            msg = obj.get("message") if isinstance(obj.get("message"), dict) else {}
            role = str(msg.get("role") or obj.get("type") or "")
            content = msg.get("content")
            txt = ""
            if isinstance(content, str):
                txt = content.strip()
            elif isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "text":
                        txt = str(part.get("text", "")).strip()
                        if txt:
                            break
            if role == "user" and txt:
                last_role = "user"
                if title.startswith("Claude "):
                    title = txt.splitlines()[0][:64]
                last_activity = f"You: {txt[:120]}"
            elif role == "assistant" and txt:
                last_role = "assistant"
                last_activity = txt.splitlines()[0][:140]

        is_recent = (now - mtime) < 20.0
        state = "running" if is_recent else (
            "needs_response" if last_role == "assistant" and last_activity.rstrip().endswith("?") else "idle"
        )
        sessions.append(
            {
                "id": sid,
                "agent": "claude",
                "title": title,
                "workspace": cwd,
                "state": state,
                "raw_status": state,
                "is_open": is_recent,
                "pid": None,
                "window_address": "",
                "window_title": "",
                "step_count": len(lines),
                "updated_at": datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat(),
                "last_activity": last_activity or "Claude Code session",
                "pending_questions": [],
                "can_resume": True,
                "can_send_terminal": False,
            }
        )
    return sessions


def _dismissed_file(config_dir: Path | None = None) -> Path:
    if config_dir is not None:
        return config_dir / "dismissed_sessions.json"
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "omalink" / "dismissed_sessions.json"


def _load_dismissed(config_dir: Path | None = None) -> dict[str, int]:
    p = _dismissed_file(config_dir)
    if not p.exists():
        return {}
    try:
        raw = json.loads(p.read_text(encoding="utf-8", errors="replace"))
        if isinstance(raw, dict):
            return {str(k): int(v) for k, v in raw.items() if isinstance(v, (int, float))}
    except Exception:
        pass
    return {}


def _save_dismissed(data: dict[str, int], config_dir: Path | None = None) -> None:
    p = _dismissed_file(config_dir)
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        # Keep most recent 200 entries
        items = list(data.items())[-200:]
        p.write_text(json.dumps(dict(items), indent=2), encoding="utf-8")
    except OSError:
        pass


def discover_sessions(
    limit: int = 20,
    agy_root: Path | None = None,
    claude_root: Path | None = None,
    config_dir: Path | None = None,
    include_dismissed: bool = False,
) -> list[dict[str, Any]]:
    """Return sorted active & recent AI agent sessions across supported Omarchy agents."""
    sessions = _discover_agy_sessions(limit=limit + 15, agy_root=agy_root)
    sessions.extend(_discover_claude_sessions(limit=min(limit, 8), claude_root=claude_root))

    if not include_dismissed:
        dismissed = _load_dismissed(config_dir)
        if dismissed:
            filtered: list[dict[str, Any]] = []
            for s in sessions:
                sid = str(s.get("id", ""))
                if sid in dismissed and not s.get("is_open") and int(s.get("step_count", 0)) <= dismissed[sid]:
                    continue
                filtered.append(s)
            sessions = filtered

    rank = {"needs_response": 0, "running": 1, "error": 2, "idle": 3}
    # Stable secondary sort by updated_at descending first, then priority bucket
    sessions.sort(key=lambda s: str(s.get("updated_at", "")), reverse=True)
    sessions.sort(
        key=lambda s: (
            rank.get(str(s.get("state", "idle")), 3),
            0 if s.get("is_open") else 1,
        )
    )
    return sessions[:limit]


def read_session_transcript(
    agent: str,
    session_id: str,
    limit: int = 40,
    agy_root: Path | None = None,
    claude_root: Path | None = None,
) -> dict[str, Any]:
    """Read clean conversation bubbles for peeking into a live or recent session."""
    safe_id = os.path.basename(session_id.strip())
    if not safe_id:
        return {"ok": False, "error": "Invalid session id", "messages": []}

    if agent == "agy":
        root = agy_root or (Path.home() / ".gemini" / "antigravity-cli")
        transcript_path = root / "brain" / safe_id / ".system_generated" / "logs" / "transcript.jsonl"
        lines = _read_tail_lines(transcript_path, max_bytes=262144)
        messages: list[dict[str, Any]] = []
        for ln in lines:
            try:
                step = json.loads(ln)
            except Exception:
                continue
            if not isinstance(step, dict):
                continue
            stype = str(step.get("type", ""))
            src = str(step.get("source", ""))
            content = str(step.get("content", "") or "").strip()
            tool_calls = step.get("tool_calls") if isinstance(step.get("tool_calls"), list) else []
            created_at = str(step.get("created_at", ""))
            step_idx = step.get("step_index", 0)
            status = str(step.get("status", ""))

            if stype == "USER_INPUT" or src == "USER_EXPLICIT":
                if content:
                    messages.append(
                        {
                            "step": step_idx,
                            "role": "user",
                            "text": content[:2000],
                            "status": status,
                            "created_at": created_at,
                        }
                    )
            elif stype == "PLANNER_RESPONSE":
                if content:
                    messages.append(
                        {
                            "step": step_idx,
                            "role": "assistant",
                            "text": content[:2500],
                            "status": status,
                            "created_at": created_at,
                        }
                    )
                for tc in tool_calls:
                    if not isinstance(tc, dict):
                        continue
                    tname = str(tc.get("name", "tool"))
                    if tname == "ask_question":
                        qs = _parse_ask_question_args(tc.get("args"))
                        messages.append(
                            {
                                "step": step_idx,
                                "role": "question",
                                "tool_name": tname,
                                "text": qs[0]["question"] if qs else "Agent asked a question",
                                "questions": qs,
                                "status": status,
                                "created_at": created_at,
                            }
                        )
                    else:
                        messages.append(
                            {
                                "step": step_idx,
                                "role": "tool",
                                "tool_name": tname,
                                "text": _summarize_tool_call(tc),
                                "status": status,
                                "created_at": created_at,
                            }
                        )
            elif stype == "GENERIC" and src == "MODEL" and content:
                # Compact tool result preview
                snippet = "\n".join(content.splitlines()[:6])[:420]
                if "Command exited with code" in content or "Made " in content or "Created file" in content or "Error" in content:
                    messages.append(
                        {
                            "step": step_idx,
                            "role": "tool_output",
                            "text": snippet,
                            "status": status,
                            "created_at": created_at,
                        }
                    )
        return {
            "ok": True,
            "agent": agent,
            "session_id": safe_id,
            "messages": messages[-max(1, min(limit, 80)) :],
        }

    if agent == "claude":
        root = claude_root or (Path.home() / ".claude" / "projects")
        found = next(root.rglob(f"{safe_id}.jsonl"), None) if root.exists() else None
        if not found:
            return {"ok": False, "error": "Claude session not found", "messages": []}
        lines = _read_tail_lines(found, max_bytes=262144)
        messages = []
        for idx, ln in enumerate(lines):
            try:
                obj = json.loads(ln)
            except Exception:
                continue
            msg = obj.get("message") if isinstance(obj.get("message"), dict) else {}
            role = str(msg.get("role") or "")
            if role not in ("user", "assistant"):
                continue
            content = msg.get("content")
            parts: list[str] = []
            if isinstance(content, str):
                parts.append(content.strip())
            elif isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "text":
                        t = str(part.get("text", "")).strip()
                        if t:
                            parts.append(t)
                    elif isinstance(part, dict) and part.get("type") == "tool_use":
                        parts.append(f"[Tool: {part.get('name', 'tool')}]")
            text = "\n".join(parts).strip()
            if text:
                messages.append(
                    {
                        "step": idx,
                        "role": role,
                        "text": text[:2000],
                        "status": "DONE",
                        "created_at": str(obj.get("timestamp", "")),
                    }
                )
        return {
            "ok": True,
            "agent": agent,
            "session_id": safe_id,
            "messages": messages[-max(1, min(limit, 80)) :],
        }

    return {"ok": False, "error": f"Unsupported agent: {agent}", "messages": []}


def send_to_live_terminal(window_address: str, text: str, submit: bool = True) -> dict[str, Any]:
    """Focus a session's Hyprland terminal window and type a reply via wtype."""
    addr = window_address.strip()
    if not addr or not addr.startswith("0x"):
        return {"ok": False, "error": "Invalid Hyprland window address"}
    if not shutil.which("hyprctl") or not shutil.which("wtype"):
        return {"ok": False, "error": "hyprctl and wtype are required for live terminal input"}
    try:
        subprocess.run(
            ["hyprctl", "dispatch", "focuswindow", f"address:{addr}"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=2.0,
        )
        time.sleep(0.14)
        if text:
            subprocess.run(["wtype", "--", text], check=True, timeout=3.0)
        if submit:
            time.sleep(0.05)
            subprocess.run(["wtype", "-k", "Return"], check=True, timeout=2.0)
        return {"ok": True, "message": "Sent reply directly to live terminal window"}
    except Exception as exc:
        return {"ok": False, "error": f"Failed to send to terminal: {exc}"}


def close_session(
    agent: str,
    session_id: str,
    step_count: int = 0,
    config_dir: Path | None = None,
    check_live_procs: bool = True,
) -> dict[str, Any]:
    """Close a live open agent session process/window (if running) and dismiss it from OmaLink."""
    safe_id = os.path.basename(session_id.strip())
    if not safe_id:
        return {"ok": False, "error": "Invalid session id"}

    closed_pid: int | None = None
    closed_window = ""

    if agent == "agy" and check_live_procs:
        open_map = _scan_open_agy_processes()
        info = open_map.get(safe_id)
        if info:
            win_addr = str(info.get("window_address", "")).strip()
            pid = info.get("pid")
            if win_addr and win_addr.startswith("0x") and shutil.which("hyprctl"):
                try:
                    subprocess.run(
                        ["hyprctl", "dispatch", "closewindow", f"address:{win_addr}"],
                        check=False,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=2.0,
                    )
                    closed_window = win_addr
                except Exception:
                    pass
            if isinstance(pid, int) and pid > 1 and pid != os.getpid():
                try:
                    os.kill(pid, signal.SIGTERM)
                    closed_pid = pid
                except OSError:
                    pass

    # Persist dismissed state so idle/closed sessions stay out of the active list
    dismissed = _load_dismissed(config_dir)
    dismissed[safe_id] = max(int(step_count or 0), dismissed.get(safe_id, 0))
    _save_dismissed(dismissed, config_dir)

    if closed_pid or closed_window:
        msg = "Closed live agent session and removed it from OmaLink"
    else:
        msg = "Dismissed session from OmaLink"
    return {
        "ok": True,
        "session_id": safe_id,
        "closed_pid": closed_pid,
        "closed_window": closed_window,
        "message": msg,
    }
