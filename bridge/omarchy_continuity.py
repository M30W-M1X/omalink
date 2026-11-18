#!/usr/bin/env python3
"""Phone-to-Omarchy Continuity helpers: notifications, calls, clipboard, app handoff."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from typing import Any
import uuid

import omarchy_desktop


_MAX_HISTORY = 50
_RECENT_NOTIFICATIONS: list[dict[str, Any]] = []
_RECENT_HANDOFFS: list[dict[str, Any]] = []
_PHONE_DEVICE: dict[str, Any] = {
    "name": "",
    "battery": None,
    "charging": False,
    "updated_at": "",
}

_URL_RE = re.compile(r"((?:https?://|spotify:)[^\s<>\"']+)", re.IGNORECASE)

_PACKAGE_TO_APP = {
    "com.android.chrome": "browser",
    "com.chrome.beta": "browser",
    "com.chrome.dev": "browser",
    "com.chrome.canary": "browser",
    "org.chromium.chrome": "browser",
    "org.mozilla.firefox": "browser",
    "org.mozilla.fenix": "browser",
    "com.brave.browser": "browser",
    "com.opera.browser": "browser",
    "com.microsoft.emmx": "browser",
    "com.vivaldi.browser": "browser",
    "com.duckduckgo.mobile.android": "browser",
    "com.spotify.music": "spotify",
    "org.thoughtcrime.securesms": "signal",
    "com.onepassword.android": "1password",
    "com.agilebits.onepassword": "1password",
    "com.termux": "terminal",
    "com.google.android.apps.nbu.files": "files",
    "com.google.android.youtube": "browser",
}

_DESKTOP_APPS: list[dict[str, Any]] = [
    {
        "id": "browser",
        "label": "Chrome / Browser",
        "bin": ["omarchy-launch-browser", "chromium", "google-chrome", "firefox"],
    },
    {
        "id": "spotify",
        "label": "Spotify",
        "bin": ["omarchy-launch-spotify", "spotify"],
    },
    {
        "id": "terminal",
        "label": "Terminal",
        "bin": ["omarchy-launch-terminal", "kitty", "alacritty", "ghostty"],
    },
    {
        "id": "files",
        "label": "Files",
        "bin": ["omarchy-launch-nautilus", "nautilus"],
    },
    {
        "id": "editor",
        "label": "Editor",
        "bin": ["omarchy-launch-editor"],
    },
    {
        "id": "signal",
        "label": "Signal",
        "bin": ["omarchy-launch-signal", "signal-desktop"],
    },
    {
        "id": "1password",
        "label": "1Password",
        "bin": ["omarchy-launch-1password", "1password"],
    },
]


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def resolve_session_env() -> dict[str, str]:
    """Build environment with Wayland, D-Bus, and Omarchy bin directories."""
    env = omarchy_desktop.resolve_wayland_env()
    uid = os.getuid()
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{uid}/bus")
    path = env.get("PATH", "")
    omarchy_bin = "/usr/share/omarchy/bin"
    if omarchy_bin not in path.split(":"):
        env["PATH"] = f"{omarchy_bin}:{path}" if path else omarchy_bin
    return env


def _spawn_detached(cmd: list[str], env: dict[str, str]) -> bool:
    try:
        subprocess.Popen(
            cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            start_new_session=True,
            close_fds=True,
        )
        return True
    except OSError:
        return False


def extract_first_url(text: str | None) -> str | None:
    """Extract the first HTTP(S) or Spotify URI from shared text."""
    if not text:
        return None
    match = _URL_RE.search(text.strip())
    if not match:
        return None
    url = match.group(1).rstrip(".,);:\"'!?]")
    return url or None


def resolve_app_key(
    app: str | None = None,
    package_name: str | None = None,
    url: str | None = None,
) -> str:
    """Resolve an Android package, app hint, or URL to a canonical Omarchy app key."""
    if app:
        cleaned = app.strip().lower()
        alias = {
            "chrome": "browser",
            "chromium": "browser",
            "firefox": "browser",
            "web": "browser",
            "nautilus": "files",
        }.get(cleaned, cleaned)
        if any(item["id"] == alias for item in _DESKTOP_APPS):
            return alias

    if package_name:
        mapped = _PACKAGE_TO_APP.get(package_name.strip().lower())
        if mapped:
            return mapped

    if url:
        lower = url.lower()
        if lower.startswith("spotify:") or "open.spotify.com" in lower:
            return "spotify"
        return "browser"

    return ""


def detect_available_apps() -> list[dict[str, Any]]:
    """Return available desktop Continuity app targets on this Omarchy system."""
    env = resolve_session_env()
    path_str = env.get("PATH", "")
    results: list[dict[str, Any]] = []
    for item in _DESKTOP_APPS:
        found = next(
            (b for b in item["bin"] if shutil.which(b, path=path_str) is not None),
            None,
        )
        results.append({
            "id": item["id"],
            "label": item["label"],
            "available": found is not None,
            "launcher": found or "",
        })
    return results


def send_desktop_notification_sync(
    *,
    title: str,
    body: str = "",
    app_name: str = "Phone",
    package_name: str = "",
    category: str = "notification",
    urgency: str = "normal",
    caller: str = "",
    can_reply: bool = False,
    reply_id: str = "",
) -> dict[str, Any]:
    """Display a notification or incoming call popup on the Omarchy desktop via notify-send."""
    env = resolve_session_env()
    norm_cat = (category or "notification").strip().lower()
    if norm_cat not in {"call", "message", "continuity", "notification"}:
        norm_cat = "notification"

    norm_urgency = (urgency or "normal").strip().lower()
    if norm_cat == "call":
        norm_urgency = "critical"
    elif norm_urgency not in {"low", "normal", "critical"}:
        norm_urgency = "normal"

    display_title = title.strip() or (caller.strip() if caller else "Notification")
    display_body = body.strip()

    if norm_cat == "call":
        summary = f"📞 Incoming Call: {caller.strip() or display_title}"
        popup_body = display_body or "Ringing on your Android phone"
        icon = "call-start"
        timeout_ms = "15000"
    elif norm_cat == "message":
        prefix = f"{app_name.strip()}: " if app_name.strip() and app_name.strip().lower() != "phone" else ""
        summary = f"💬 {prefix}{display_title}"
        popup_body = display_body or "New message"
        icon = "mail-message-new"
        timeout_ms = "8000"
    elif norm_cat == "continuity":
        summary = f"✨ {display_title}"
        popup_body = display_body
        icon = "computer"
        timeout_ms = "5000"
    else:
        prefix = f"{app_name.strip()}: " if app_name.strip() and app_name.strip().lower() != "phone" else ""
        summary = f"📱 {prefix}{display_title}"
        popup_body = display_body
        icon = "phone"
        timeout_ms = "6500"

    notified = False
    notify_bin = shutil.which("notify-send", path=env.get("PATH"))
    if notify_bin:
        cmd = [
            notify_bin,
            "-a",
            "Omarchy Wizard Phone",
            "-u",
            norm_urgency,
            "-i",
            icon,
            "-t",
            timeout_ms,
            "--",
            summary,
            popup_body,
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=3.0, env=env)
            notified = res.returncode == 0
        except (subprocess.SubprocessError, OSError):
            notified = False

    entry = {
        "id": uuid.uuid4().hex[:10],
        "ts": _utc_now(),
        "category": norm_cat,
        "urgency": norm_urgency,
        "app_name": app_name.strip() or "Phone",
        "package_name": package_name.strip(),
        "title": summary,
        "body": popup_body,
        "notified": notified,
        "can_reply": bool(can_reply and reply_id.strip()),
        "reply_id": reply_id.strip(),
    }
    _RECENT_NOTIFICATIONS.insert(0, entry)
    del _RECENT_NOTIFICATIONS[_MAX_HISTORY:]
    return entry


def update_phone_device_state(
    *,
    name: str = "",
    battery: int | None = None,
    charging: bool = False,
) -> dict[str, Any]:
    if name.strip():
        _PHONE_DEVICE["name"] = name.strip()[:48]
    if battery is not None:
        _PHONE_DEVICE["battery"] = max(0, min(100, int(battery)))
    _PHONE_DEVICE["charging"] = bool(charging)
    _PHONE_DEVICE["updated_at"] = _utc_now()
    return dict(_PHONE_DEVICE)


def get_phone_device_state() -> dict[str, Any]:
    return dict(_PHONE_DEVICE)


def latest_replyable_notification() -> dict[str, Any] | None:
    for item in _RECENT_NOTIFICATIONS:
        if item.get("can_reply") and item.get("reply_id"):
            return dict(item)
    return None


def clipboard_history_path() -> Path:
    return Path.home() / ".local" / "state" / "omarchy" / "clipboard-history.json"


def clipboard_history_mtime() -> float:
    p = clipboard_history_path()
    try:
        return p.stat().st_mtime if p.is_file() else 0.0
    except OSError:
        return 0.0


def read_clipboard_history_sync(limit: int = 20) -> list[str]:
    """Read Omarchy's native clipboard history JSON entries."""
    p = clipboard_history_path()
    if not p.is_file():
        return []
    try:
        raw = json.loads(p.read_text(encoding="utf-8", errors="replace"))
        if not isinstance(raw, list):
            return []
        items: list[str] = []
        for entry in raw:
            if isinstance(entry, dict) and entry.get("type") == "text":
                txt = str(entry.get("text", "")).strip()
                if txt and txt not in items:
                    items.append(txt[:2000])
            if len(items) >= limit:
                break
        return items
    except Exception:
        return []


def set_clipboard_sync(text: str, notify: bool = False) -> dict[str, Any]:
    """Write UTF-8 text to the Wayland desktop clipboard via `wl-copy`."""
    env = resolve_session_env()
    wl_copy = shutil.which("wl-copy", path=env.get("PATH"))
    ok = False
    message = ""

    if not wl_copy:
        message = "wl-copy is not installed on this host."
    else:
        try:
            proc = subprocess.Popen(
                [wl_copy],
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=env,
                close_fds=True,
            )
            proc.communicate(text.encode("utf-8"), timeout=2.0)
            ok = proc.returncode == 0
            message = "Clipboard synced to Omarchy." if ok else f"wl-copy exited {proc.returncode}"
        except (subprocess.SubprocessError, OSError) as exc:
            message = str(exc)

    if ok and notify:
        preview = text.strip().replace("\n", " ")
        if len(preview) > 90:
            preview = preview[:89] + "…"
        send_desktop_notification_sync(
            title="Clipboard from Phone",
            body=preview,
            app_name="Continuity",
            category="continuity",
        )

    return {"ok": ok, "length": len(text), "preview": text[:160], "message": message}


def get_clipboard_sync(max_chars: int = 16000) -> dict[str, Any]:
    """Read current text from the Wayland desktop clipboard via `wl-paste`."""
    env = resolve_session_env()
    wl_paste = shutil.which("wl-paste", path=env.get("PATH"))
    if not wl_paste:
        return {"ok": False, "text": "", "error": "wl-paste not found"}

    try:
        res = subprocess.run(
            [wl_paste, "--no-newline"],
            capture_output=True,
            timeout=2.0,
            env=env,
        )
        if res.returncode != 0:
            return {"ok": True, "text": "", "empty": True}
        text = res.stdout.decode("utf-8", errors="replace")
        truncated = len(text) > max_chars
        if truncated:
            text = text[:max_chars]
        return {"ok": True, "text": text, "empty": len(text) == 0, "truncated": truncated}
    except (subprocess.SubprocessError, OSError) as exc:
        return {"ok": False, "text": "", "error": str(exc)}


def _launch_app_or_url(
    app_key: str,
    url: str | None,
    env: dict[str, str],
) -> tuple[bool, str, str]:
    path_str = env.get("PATH", "")

    if url:
        # Prefer native Spotify app for spotify: URIs, browser for web links, xdg-open otherwise
        if app_key == "spotify" and url.lower().startswith("spotify:"):
            spotify_bin = shutil.which("spotify", path=path_str)
            if spotify_bin and _spawn_detached([spotify_bin, f"--uri={url}"], env):
                return True, f"Opened in Spotify: {url}", "spotify"

        if url.lower().startswith(("http://", "https://")):
            launcher = shutil.which("omarchy-launch-browser", path=path_str) or shutil.which(
                "xdg-open", path=path_str
            )
            if launcher and _spawn_detached([launcher, url], env):
                return True, f"Opened link on Omarchy: {url}", Path(launcher).name

        xdg = shutil.which("xdg-open", path=path_str)
        if xdg and _spawn_detached([xdg, url], env):
            return True, f"Opened URI on Omarchy: {url}", "xdg-open"
        return False, "No URL launcher (omarchy-launch-browser / xdg-open) found.", ""

    for item in _DESKTOP_APPS:
        if item["id"] == app_key:
            for bin_name in item["bin"]:
                resolved = shutil.which(bin_name, path=path_str)
                if resolved and _spawn_detached([resolved], env):
                    return True, f"Launched {item['label']} on Omarchy.", bin_name
            return False, f"{item['label']} is not available on this host.", ""

    return False, "Nothing to open or copy.", ""


def handoff_to_desktop_sync(
    *,
    url: str = "",
    text: str = "",
    subject: str = "",
    app: str = "",
    package_name: str = "",
    copy_to_clipboard: bool = True,
) -> dict[str, Any]:
    """Continue a URL, app session, or snippet from the phone on Omarchy."""
    env = resolve_session_env()
    raw_url = url.strip() or (extract_first_url(text) or "")
    raw_text = text.strip()
    resolved_app = resolve_app_key(app=app, package_name=package_name, url=raw_url)

    ok = False
    kind = "clipboard"
    launcher = ""
    message = ""

    if raw_url or resolved_app:
        ok, message, launcher = _launch_app_or_url(resolved_app or "browser", raw_url or None, env)
        kind = "url" if raw_url else "app"
        if raw_text and copy_to_clipboard and not raw_url:
            set_clipboard_sync(raw_text, notify=False)
        elif raw_url and copy_to_clipboard:
            set_clipboard_sync(raw_url, notify=False)

        if ok:
            notify_body = subject.strip() or raw_url or f"Opened {resolved_app}"
            send_desktop_notification_sync(
                title="Continued from Phone",
                body=notify_body,
                app_name="Continuity",
                category="continuity",
            )
    elif raw_text:
        clip_res = set_clipboard_sync(raw_text, notify=True)
        ok = clip_res["ok"]
        message = clip_res["message"]
        launcher = "wl-copy"
        kind = "clipboard"
    else:
        return {"ok": False, "error": "Provide 'url', 'text', or 'app' for handoff."}

    record = {
        "id": uuid.uuid4().hex[:10],
        "ts": _utc_now(),
        "ok": ok,
        "kind": kind,
        "app": resolved_app,
        "url": raw_url,
        "subject": subject.strip(),
        "launcher": launcher,
        "message": message,
    }
    _RECENT_HANDOFFS.insert(0, record)
    del _RECENT_HANDOFFS[_MAX_HISTORY:]
    return record


async def notify_desktop(**kwargs: Any) -> dict[str, Any]:
    return await asyncio.to_thread(send_desktop_notification_sync, **kwargs)


async def set_clipboard(text: str, notify: bool = False) -> dict[str, Any]:
    return await asyncio.to_thread(set_clipboard_sync, text, notify)


async def get_clipboard() -> dict[str, Any]:
    return await asyncio.to_thread(get_clipboard_sync)


async def handoff_to_desktop(**kwargs: Any) -> dict[str, Any]:
    return await asyncio.to_thread(handoff_to_desktop_sync, **kwargs)


async def read_continuity_state() -> dict[str, Any]:
    clip, apps, history = await asyncio.gather(
        get_clipboard(),
        asyncio.to_thread(detect_available_apps),
        asyncio.to_thread(read_clipboard_history_sync, 20),
    )
    return {
        "clipboard": clip,
        "clipboard_history": history,
        "apps": apps,
        "phone": get_phone_device_state(),
        "replyable_notification": latest_replyable_notification(),
        "recent_notifications": list(_RECENT_NOTIFICATIONS[:20]),
        "recent_handoffs": list(_RECENT_HANDOFFS[:20]),
    }
