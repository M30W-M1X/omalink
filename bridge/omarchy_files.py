#!/usr/bin/env python3
"""Remote File Explorer helpers for Omarchy Wizard Bridge."""

from __future__ import annotations

import asyncio
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


MAX_READ_BYTES = 131_072
MAX_DIR_ENTRIES = 400
MAX_TRANSFER_BYTES = 40 * 1024 * 1024  # 40 MB safety cap for phone <-> PC transfers


def _bookmarks() -> list[dict[str, str]]:
    home = Path.home()
    candidates = [
        ("Home", home),
        ("Projects", home / "Projects"),
        ("Work", home / "Work"),
        ("Downloads", home / "Downloads"),
        ("Documents", home / "Documents"),
        ("Config", home / ".config"),
    ]
    return [
        {"label": label, "path": str(path)}
        for label, path in candidates
        if path.is_dir()
    ]


def _resolve_existing_path(raw_path: str | None, *, fallback_home: bool = False) -> Path:
    if not raw_path or not raw_path.strip():
        return Path.home().resolve()
    target = Path(raw_path).expanduser().resolve()
    if not target.exists() and fallback_home:
        return Path.home().resolve()
    return target


def _resolve_entry_no_follow(raw_path: str) -> Path:
    """Resolve parent directory canonically WITHOUT following a final symlink component."""
    cleaned = raw_path.strip()
    if not cleaned:
        raise ValueError("Path is required")
    stripped = cleaned.rstrip("/")
    if not stripped:
        return Path("/")
    expanded = Path(stripped).expanduser()
    name = expanded.name
    if not name or name in {".", ".."}:
        raise ValueError("Invalid target entry name")
    parent = expanded.parent.resolve(strict=True)
    return parent / name


def _safe_child_name(name: str) -> str:
    cleaned = name.strip()
    if not cleaned or cleaned in {".", ".."} or "/" in cleaned or "\\" in cleaned or "\x00" in cleaned:
        raise ValueError("Invalid filename")
    return cleaned


def _format_entry(entry: Path) -> dict[str, Any]:
    is_symlink = entry.is_symlink()
    try:
        st = entry.lstat() if is_symlink else entry.stat()
        is_dir = False if is_symlink else entry.is_dir()
        size = 0 if is_dir else st.st_size
        modified = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat()
    except OSError:
        is_dir = False
        size = 0
        modified = ""
    return {
        "name": entry.name,
        "path": str(entry),
        "is_dir": is_dir,
        "is_symlink": is_symlink,
        "size": size,
        "modified": modified,
        "extension": "" if is_dir else entry.suffix.lstrip(".").lower(),
    }


def list_directory_sync(raw_path: str | None = None, *, show_hidden: bool = False) -> dict[str, Any]:
    target = _resolve_existing_path(raw_path, fallback_home=True)
    if target.is_file():
        target = target.parent
    if not target.is_dir():
        raise FileNotFoundError(f"Directory not found: {target}")

    entries: list[dict[str, Any]] = []
    truncated = False
    raw_items = list(target.iterdir())
    if not show_hidden:
        raw_items = [p for p in raw_items if not p.name.startswith(".")]

    # Sort directories first, then files case-insensitively
    raw_items.sort(key=lambda p: (not p.is_dir(), p.name.lower()))
    if len(raw_items) > MAX_DIR_ENTRIES:
        raw_items = raw_items[:MAX_DIR_ENTRIES]
        truncated = True

    for item in raw_items:
        entries.append(_format_entry(item))

    parent = str(target.parent) if target.parent != target else None
    return {
        "path": str(target),
        "parent": parent,
        "show_hidden": show_hidden,
        "truncated": truncated,
        "bookmarks": _bookmarks(),
        "entries": entries,
    }


def read_file_preview_sync(raw_path: str, max_bytes: int = MAX_READ_BYTES) -> dict[str, Any]:
    target = _resolve_existing_path(raw_path)
    if not target.exists() or not target.is_file():
        raise FileNotFoundError(f"File not found: {raw_path}")

    st = target.stat()
    raw = target.read_bytes()[: max_bytes + 1]
    truncated = len(raw) > max_bytes
    if truncated:
        raw = raw[:max_bytes]

    # Detect binary data by checking NUL bytes or strict UTF-8 decoding
    if b"\x00" in raw:
        return {
            "path": str(target),
            "name": target.name,
            "size": st.st_size,
            "is_binary": True,
            "truncated": False,
            "content": "",
        }
    try:
        text = raw.decode("utf-8")
        return {
            "path": str(target),
            "name": target.name,
            "size": st.st_size,
            "is_binary": False,
            "truncated": truncated,
            "content": text,
        }
    except UnicodeDecodeError:
        return {
            "path": str(target),
            "name": target.name,
            "size": st.st_size,
            "is_binary": True,
            "truncated": False,
            "content": "",
        }


def create_directory_sync(parent_path: str, name: str) -> dict[str, Any]:
    parent = _resolve_existing_path(parent_path)
    if not parent.is_dir():
        raise FileNotFoundError(f"Parent directory not found: {parent_path}")
    safe_name = _safe_child_name(name)
    created = parent / safe_name
    created.mkdir(exist_ok=False)
    return {"ok": True, "entry": _format_entry(created)}


def rename_entry_sync(raw_path: str, new_name: str) -> dict[str, Any]:
    target = _resolve_entry_no_follow(raw_path)
    if not os.path.lexists(target):
        raise FileNotFoundError(f"Entry not found: {raw_path}")
    safe_name = _safe_child_name(new_name)
    dest = target.parent / safe_name
    if os.path.lexists(dest):
        raise FileExistsError(f"Destination already exists: {dest.name}")
    target.rename(dest)
    return {"ok": True, "entry": _format_entry(dest)}


def open_on_desktop_sync(raw_path: str) -> dict[str, Any]:
    target = _resolve_existing_path(raw_path)
    if not target.exists():
        raise FileNotFoundError(f"Entry not found: {raw_path}")
    subprocess.Popen(
        ["xdg-open", str(target)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    return {"ok": True, "message": f"Opened {target.name} on desktop"}


def trash_entry_sync(raw_path: str) -> dict[str, Any]:
    target = _resolve_entry_no_follow(raw_path)
    if not os.path.lexists(target):
        raise FileNotFoundError(f"Entry not found: {raw_path}")
    if target == Path.home().resolve() or target == Path("/"):
        raise ValueError("Refusing to trash root or home directory")
    if not shutil.which("gio"):
        raise RuntimeError("gio trash is unavailable on this host")
    res = subprocess.run(["gio", "trash", "--", str(target)], capture_output=True, text=True, timeout=5.0)
    if res.returncode != 0:
        raise RuntimeError(res.stderr.strip() or "Failed to move item to Trash")
    return {"ok": True, "message": f"Moved {target.name} to Trash"}


async def list_directory(raw_path: str | None = None, *, show_hidden: bool = False) -> dict[str, Any]:
    return await asyncio.to_thread(list_directory_sync, raw_path, show_hidden=show_hidden)


async def read_file_preview(raw_path: str) -> dict[str, Any]:
    return await asyncio.to_thread(read_file_preview_sync, raw_path)


async def create_directory(parent_path: str, name: str) -> dict[str, Any]:
    return await asyncio.to_thread(create_directory_sync, parent_path, name)


async def rename_entry(raw_path: str, new_name: str) -> dict[str, Any]:
    return await asyncio.to_thread(rename_entry_sync, raw_path, new_name)


async def open_on_desktop(raw_path: str) -> dict[str, Any]:
    return await asyncio.to_thread(open_on_desktop_sync, raw_path)


def save_uploaded_file_sync(
    filename: str,
    data: bytes,
    dest_dir: str | None = None,
) -> dict[str, Any]:
    """Save an uploaded file from phone into dest_dir (default ~/Downloads), avoiding collisions."""
    if len(data) > MAX_TRANSFER_BYTES:
        raise ValueError(f"File exceeds {MAX_TRANSFER_BYTES // (1024 * 1024)} MB limit")
    safe_name = _safe_child_name(Path(filename).name if filename else "shared_file")
    if dest_dir and dest_dir.strip():
        target_dir = _resolve_existing_path(dest_dir, fallback_home=False)
    else:
        target_dir = (Path.home() / "Downloads").resolve()
        target_dir.mkdir(parents=True, exist_ok=True)
    if not target_dir.is_dir():
        raise FileNotFoundError(f"Destination directory not found: {target_dir}")

    dest = target_dir / safe_name
    if dest.exists():
        stem = dest.stem
        suffix = dest.suffix
        for idx in range(1, 1000):
            candidate = target_dir / f"{stem} ({idx}){suffix}"
            if not candidate.exists():
                dest = candidate
                break

    dest.write_bytes(data)
    return {
        "ok": True,
        "path": str(dest),
        "name": dest.name,
        "size": len(data),
        "entry": _format_entry(dest),
    }


def read_file_bytes_sync(raw_path: str) -> tuple[str, bytes]:
    """Read raw file bytes for download to phone."""
    target = _resolve_existing_path(raw_path)
    if not target.exists() or not target.is_file():
        raise FileNotFoundError(f"File not found: {raw_path}")
    size = target.stat().st_size
    if size > MAX_TRANSFER_BYTES:
        raise ValueError(f"File exceeds {MAX_TRANSFER_BYTES // (1024 * 1024)} MB download limit")
    return target.name, target.read_bytes()


async def trash_entry(raw_path: str) -> dict[str, Any]:
    return await asyncio.to_thread(trash_entry_sync, raw_path)


async def save_uploaded_file(
    filename: str,
    data: bytes,
    dest_dir: str | None = None,
) -> dict[str, Any]:
    return await asyncio.to_thread(save_uploaded_file_sync, filename, data, dest_dir)


async def read_file_bytes(raw_path: str) -> tuple[str, bytes]:
    return await asyncio.to_thread(read_file_bytes_sync, raw_path)
