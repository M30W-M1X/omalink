#!/usr/bin/env python3
"""OS Control Plane helpers for Omarchy Wizard Bridge.

Reads system telemetry, audio/media, display, Hyprland workspaces, Omarchy toggles,
themes, and security state, and dispatches allowlisted OS control actions via
native Omarchy CLI scripts and standard desktop utilities.
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import shutil
import socket
import subprocess
from pathlib import Path
from typing import Any


def _run_cmd(cmd: list[str], timeout: float = 4.0) -> tuple[int, str, str]:
    """Run a quick command synchronously and capture (returncode, stdout, stderr)."""
    try:
        res = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except (FileNotFoundError, subprocess.SubprocessError, OSError) as exc:
        return 127, "", str(exc)


def _spawn_detached(cmd: list[str]) -> bool:
    """Launch a desktop GUI/session command detached without blocking the bridge."""
    try:
        subprocess.Popen(
            cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except OSError:
        return False


def _read_uptime_seconds() -> int:
    try:
        raw = Path("/proc/uptime").read_text(encoding="utf-8").split()[0]
        return int(float(raw))
    except Exception:
        return 0


def _read_memory_info() -> dict[str, float]:
    total_kb = 0
    avail_kb = 0
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            if line.startswith("MemTotal:"):
                total_kb = int(line.split()[1])
            elif line.startswith("MemAvailable:"):
                avail_kb = int(line.split()[1])
    except Exception:
        return {"used_gb": 0.0, "total_gb": 0.0, "percent": 0.0}
    if total_kb <= 0:
        return {"used_gb": 0.0, "total_gb": 0.0, "percent": 0.0}
    used_kb = max(0, total_kb - avail_kb)
    return {
        "used_gb": round(used_kb / 1024 / 1024, 1),
        "total_gb": round(total_kb / 1024 / 1024, 1),
        "percent": round((used_kb / total_kb) * 100.0, 1),
    }


def _read_cpu_and_load() -> dict[str, Any]:
    load_avg = "0.00"
    try:
        load_avg = Path("/proc/loadavg").read_text(encoding="utf-8").split()[0]
    except Exception:
        pass

    cpu_percent = 0.0
    if shutil.which("omarchy-system-stats"):
        rc, out, _ = _run_cmd(["omarchy-system-stats"], timeout=3.0)
        if rc == 0:
            for line in out.splitlines():
                if line.startswith("cpu\t"):
                    raw_val = line.split("\t", 1)[1].rstrip("%").strip()
                    try:
                        cpu_percent = float(raw_val)
                    except ValueError:
                        pass
                    break
    return {"cpu_percent": cpu_percent, "load_avg": load_avg}


def _read_battery() -> dict[str, Any]:
    supply_dir = Path("/sys/class/power_supply")
    if not supply_dir.is_dir():
        return {"present": False, "percent": 0, "status": "none"}
    for child in sorted(supply_dir.iterdir()):
        if not child.name.startswith("BAT"):
            continue
        try:
            cap = int((child / "capacity").read_text(encoding="utf-8").strip())
            status = (child / "status").read_text(encoding="utf-8").strip()
            return {"present": True, "percent": cap, "status": status}
        except Exception:
            continue
    return {"present": False, "percent": 0, "status": "none"}


def _parse_wpctl_volume(target: str) -> tuple[int, bool]:
    if not shutil.which("wpctl"):
        return 0, False
    rc, out, _ = _run_cmd(["wpctl", "get-volume", target], timeout=2.0)
    if rc != 0 or not out:
        return 0, False
    muted = "MUTED" in out
    match = re.search(r"([0-9]+(?:\.[0-9]+)?)", out)
    percent = int(round(float(match.group(1)) * 100)) if match else 0
    return max(0, min(150, percent)), muted


def _read_audio_state() -> dict[str, Any]:
    vol, muted = _parse_wpctl_volume("@DEFAULT_AUDIO_SINK@")
    _, mic_muted = _parse_wpctl_volume("@DEFAULT_AUDIO_SOURCE@")

    default_sink = ""
    if shutil.which("omarchy-audio-output-sink"):
        rc, out, _ = _run_cmd(["omarchy-audio-output-sink"], timeout=2.0)
        if rc == 0:
            default_sink = out.strip()
    if not default_sink and shutil.which("pactl"):
        rc, out, _ = _run_cmd(["pactl", "get-default-sink"], timeout=2.0)
        if rc == 0:
            default_sink = out.strip()

    sinks: list[dict[str, Any]] = []
    if shutil.which("pactl"):
        env_rc, out, _ = _run_cmd(["env", "LC_ALL=C", "pactl", "list", "sinks"], timeout=2.5)
        if env_rc == 0 and out:
            current: dict[str, Any] | None = None
            for line in out.splitlines():
                if line.startswith("Sink #"):
                    if current and current.get("name"):
                        sinks.append(current)
                    current = {"id": line.split("#", 1)[1].strip(), "name": "", "description": "", "active": False}
                elif current is not None:
                    stripped = line.strip()
                    if stripped.startswith("Name:"):
                        name = stripped.split(":", 1)[1].strip()
                        current["name"] = name
                        current["active"] = (name == default_sink)
                    elif stripped.startswith("Description:"):
                        current["description"] = stripped.split(":", 1)[1].strip()
            if current and current.get("name"):
                sinks.append(current)

    player: dict[str, Any] = {"available": False, "status": "Stopped", "title": "", "artist": ""}
    if shutil.which("playerctl"):
        rc, status_out, _ = _run_cmd(["playerctl", "status"], timeout=1.5)
        if rc == 0 and status_out:
            _, meta_out, _ = _run_cmd(
                ["playerctl", "metadata", "--format", "{{title}}\t{{artist}}"],
                timeout=1.5,
            )
            title, artist = "", ""
            if "\t" in meta_out:
                title, artist = meta_out.split("\t", 1)
            player = {
                "available": True,
                "status": status_out.strip(),
                "title": title.strip(),
                "artist": artist.strip(),
            }

    return {
        "volume": vol,
        "muted": muted,
        "mic_muted": mic_muted,
        "default_sink": default_sink,
        "sinks": sinks,
        "player": player,
    }


def _read_brightness() -> dict[str, Any]:
    if shutil.which("omarchy-brightness-display"):
        rc, out, _ = _run_cmd(["omarchy-brightness-display"], timeout=2.0)
        if rc == 0 and out:
            match = re.search(r"([0-9]+)", out)
            if match:
                return {"available": True, "percent": max(0, min(100, int(match.group(1))))}
    if shutil.which("brightnessctl"):
        rc, out, _ = _run_cmd(["brightnessctl", "--class=backlight", "-m"], timeout=1.5)
        if rc == 0 and out:
            parts = out.splitlines()[0].split(",")
            if len(parts) >= 4 and parts[3].endswith("%"):
                try:
                    return {"available": True, "percent": int(parts[3].rstrip("%"))}
                except ValueError:
                    pass
    return {"available": False, "percent": 0}


def _read_hyprland_state() -> dict[str, Any]:
    workspaces: list[dict[str, Any]] = []
    active_window: dict[str, Any] = {"title": "", "class": "", "address": ""}
    if not shutil.which("hyprctl"):
        return {"workspaces": workspaces, "active_window": active_window}

    active_ws_id: int | None = None
    rc, ws_out, _ = _run_cmd(["hyprctl", "activeworkspace", "-j"], timeout=2.0)
    if rc == 0 and ws_out:
        try:
            active_ws_id = int(json.loads(ws_out).get("id"))
        except Exception:
            pass

    rc, list_out, _ = _run_cmd(["hyprctl", "workspaces", "-j"], timeout=2.0)
    if rc == 0 and list_out:
        try:
            raw_list = json.loads(list_out)
            if isinstance(raw_list, list):
                for item in raw_list:
                    if not isinstance(item, dict):
                        continue
                    ws_id = int(item.get("id", 0))
                    if ws_id <= 0:
                        continue
                    workspaces.append({
                        "id": ws_id,
                        "name": str(item.get("name", ws_id)),
                        "windows": int(item.get("windows", 0)),
                        "active": ws_id == active_ws_id,
                    })
                workspaces.sort(key=lambda w: w["id"])
        except Exception:
            pass

    rc, win_out, _ = _run_cmd(["hyprctl", "activewindow", "-j"], timeout=2.0)
    if rc == 0 and win_out:
        try:
            win = json.loads(win_out)
            if isinstance(win, dict):
                active_window = {
                    "title": str(win.get("title") or ""),
                    "class": str(win.get("class") or ""),
                    "address": str(win.get("address") or ""),
                }
        except Exception:
            pass

    return {"workspaces": workspaces, "active_window": active_window}


def _toggle_flag_exists(name: str) -> bool:
    return (Path.home() / ".local" / "state" / "omarchy" / "toggles" / name).exists()


def _read_toggles_state() -> dict[str, Any]:
    nightlight = False
    if shutil.which("omarchy-toggle-nightlight"):
        rc, out, _ = _run_cmd(["omarchy-toggle-nightlight", "--status"], timeout=2.0)
        if rc == 0 and out.startswith("{"):
            try:
                nightlight = bool(json.loads(out).get("enabled", False))
            except Exception:
                pass

    stay_awake = False
    if shutil.which("omarchy-toggle-idle"):
        rc, out, _ = _run_cmd(["omarchy-toggle-idle", "status"], timeout=2.0)
        if rc == 0 and out.startswith("{"):
            try:
                stay_awake = bool(json.loads(out).get("enabled", False))
            except Exception:
                pass

    animations_off = False
    if shutil.which("omarchy-hyprland-toggle-enabled"):
        rc, _, _ = _run_cmd(["omarchy-hyprland-toggle-enabled", "no-animations"], timeout=1.5)
        animations_off = (rc == 0)

    return {
        "nightlight": nightlight,
        "stay_awake": stay_awake,
        "bar_hidden": _toggle_flag_exists("bar-off"),
        "screensaver_off": _toggle_flag_exists("screensaver-off"),
        "animations_off": animations_off,
    }


def _read_theme_state() -> dict[str, Any]:
    current = ""
    themes: list[str] = []
    if shutil.which("omarchy-theme-current"):
        rc, out, _ = _run_cmd(["omarchy-theme-current"], timeout=2.0)
        if rc == 0:
            current = out.strip()
    if shutil.which("omarchy-theme-list"):
        rc, out, _ = _run_cmd(["omarchy-theme-list"], timeout=2.0)
        if rc == 0:
            themes = [line.strip() for line in out.splitlines() if line.strip()]
    return {"current": current, "themes": themes}


def _read_security_state() -> dict[str, Any]:
    passwordless_sudo = False
    if shutil.which("omarchy-sudo-passwordless"):
        rc, _, _ = _run_cmd(["omarchy-sudo-passwordless", "--active"], timeout=2.5)
        passwordless_sudo = (rc == 0)

    bluetooth_powered: bool | None = None
    if shutil.which("bluetoothctl"):
        rc, out, _ = _run_cmd(["bluetoothctl", "show"], timeout=2.0)
        if rc == 0 and out:
            for line in out.splitlines():
                if "Powered:" in line:
                    bluetooth_powered = line.strip().endswith("yes")
                    break

    tailscale_active: bool | None = None
    if shutil.which("tailscale"):
        rc, out, _ = _run_cmd(["tailscale", "status", "--json"], timeout=2.0)
        if rc == 0 and out.startswith("{"):
            try:
                tailscale_active = str(json.loads(out).get("BackendState", "")) == "Running"
            except Exception:
                pass

    return {
        "passwordless_sudo": passwordless_sudo,
        "bluetooth_powered": bluetooth_powered,
        "tailscale_active": tailscale_active,
    }


def read_system_state_sync() -> dict[str, Any]:
    """Collect full OS control-plane snapshot synchronously (called via thread)."""
    os_version = "unknown"
    if shutil.which("omarchy-version"):
        rc, out, _ = _run_cmd(["omarchy-version"], timeout=1.5)
        if rc == 0 and out:
            os_version = out.splitlines()[0].strip()

    cpu_load = _read_cpu_and_load()
    return {
        "hostname": socket.gethostname(),
        "os_version": os_version,
        "uptime_seconds": _read_uptime_seconds(),
        "cpu_percent": cpu_load["cpu_percent"],
        "load_avg": cpu_load["load_avg"],
        "memory": _read_memory_info(),
        "battery": _read_battery(),
        "audio": _read_audio_state(),
        "brightness": _read_brightness(),
        "hyprland": _read_hyprland_state(),
        "toggles": _read_toggles_state(),
        "theme": _read_theme_state(),
        "security": _read_security_state(),
    }


async def read_system_state() -> dict[str, Any]:
    return await asyncio.to_thread(read_system_state_sync)


def _action_result(ok: bool, message: str, *, state: dict[str, Any] | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"ok": ok, "message": message}
    if state is not None:
        payload["state"] = state
    return payload


def _validate_theme(name: str) -> str | None:
    themes = _read_theme_state()["themes"]
    for item in themes:
        if item == name:
            return item
    return None


def _run_omarchy_action(cmd: list[str], success_msg: str, fail_prefix: str = "Action failed") -> tuple[bool, str]:
    rc, out, err = _run_cmd(cmd, timeout=6.0)
    if rc == 0:
        return True, success_msg
    detail = err or out or f"exit {rc}"
    return False, f"{fail_prefix}: {detail}"


# Mapping for simple zero-argument Omarchy toggle/restart/system actions.
_SIMPLE_COMMANDS: dict[str, tuple[list[str], str]] = {
    "audio.toggle_mute": (["omarchy-audio-output-volume", "mute-toggle"], "Toggled audio mute"),
    "audio.toggle_mic_mute": (["omarchy-audio-input-mute"], "Toggled microphone mute"),
    "media.play_pause": (["playerctl", "play-pause"], "Toggled media playback"),
    "media.next": (["playerctl", "next"], "Skipped to next track"),
    "media.previous": (["playerctl", "previous"], "Returned to previous track"),
    "theme.next_bg": (["omarchy-theme-bg-next"], "Cycled desktop wallpaper"),
    "toggle.nightlight": (["omarchy-toggle-nightlight"], "Toggled nightlight"),
    "toggle.idle": (["omarchy-toggle-idle"], "Toggled stay-awake mode"),
    "toggle.bar": (["omarchy-toggle-bar"], "Toggled Omarchy top bar"),
    "toggle.screensaver": (["omarchy-toggle-screensaver"], "Toggled screensaver lock"),
    "toggle.animations": (["omarchy-toggle-animations"], "Toggled Hyprland animations"),
    "toggle.dnd": (["omarchy-toggle-notification-silencing"], "Toggled Do Not Disturb"),
    "toggle.bluetooth": (["omarchy-bluetooth-power", "toggle"], "Toggled Bluetooth power"),
    "system.lock": (["omarchy-system-lock"], "Locked desktop session"),
    "system.restart_audio": (["omarchy-restart-audio"], "Restarted audio stack"),
    "system.restart_wifi": (["omarchy-restart-wifi"], "Restarted Wi-Fi stack"),
    "system.restart_bluetooth": (["omarchy-restart-bluetooth"], "Restarted Bluetooth stack"),
    "system.restart_shell": (["omarchy-restart-shell"], "Restarted Omarchy shell"),
    "system.logout": (["omarchy-system", "logout"], "Logging out session"),
    "system.reboot": (["omarchy-system", "reboot"], "Rebooting machine"),
    "system.shutdown": (["omarchy-system", "shutdown"], "Shutting down machine"),
    "hyprland.close_active": (["hyprctl", "dispatch", "killactive"], "Closed active window"),
    "security.sudo_disable": (["omarchy-sudo-passwordless", "--disable"], "Disabled passwordless sudo"),
}


def execute_control_action_sync(action: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    """Dispatch an allowlisted OS control plane action synchronously."""
    params = params or {}

    if action in _SIMPLE_COMMANDS:
        cmd, msg = _SIMPLE_COMMANDS[action]
        ok, status_msg = _run_omarchy_action(cmd, msg)
        return _action_result(ok, status_msg, state=read_system_state_sync())

    if action == "audio.set_volume":
        try:
            pct = max(0, min(100, int(params.get("percent", 50))))
        except (TypeError, ValueError):
            return _action_result(False, "Invalid volume percent")
        rc, sink, err = _run_cmd(["omarchy-audio-output-sink"], timeout=2.0)
        if rc != 0 or not sink:
            return _action_result(False, f"No active audio sink: {err}")
        _run_cmd(["pactl", "set-sink-mute", sink, "0"], timeout=2.0)
        ok, msg = _run_omarchy_action(["pactl", "set-sink-volume", sink, f"{pct}%"], f"Volume set to {pct}%")
        if ok and shutil.which("omarchy-osd"):
            _spawn_detached(["omarchy-osd", "-i", "volume-muted" if pct == 0 else "volume-high", "-p", str(pct)])
        return _action_result(ok, msg, state=read_system_state_sync())

    if action == "audio.step_volume":
        try:
            delta = int(params.get("delta", 5))
        except (TypeError, ValueError):
            return _action_result(False, "Invalid volume delta")
        delta = max(-25, min(25, delta))
        arg = f"+{delta}" if delta >= 0 else str(delta)
        ok, msg = _run_omarchy_action(["omarchy-audio-output-volume", arg], f"Adjusted volume ({arg}%)")
        return _action_result(ok, msg, state=read_system_state_sync())

    if action == "audio.set_sink":
        node_id = str(params.get("id", "")).strip()
        sink_name = str(params.get("name", "")).strip()
        if not re.fullmatch(r"[0-9]+", node_id) or not re.fullmatch(r"[A-Za-z0-9_.:-]+", sink_name):
            return _action_result(False, "Invalid audio sink identifier")
        ok, msg = _run_omarchy_action(
            ["omarchy-audio-output-set-default", node_id, sink_name],
            f"Switched audio output to {sink_name}",
        )
        return _action_result(ok, msg, state=read_system_state_sync())

    if action == "brightness.step":
        delta = str(params.get("delta", "+10%")).strip()
        if not re.fullmatch(r"(\+[0-9]{1,3}%|[0-9]{1,3}%-|[0-9]{1,3}%|on|off)", delta):
            return _action_result(False, "Invalid brightness step")
        ok, msg = _run_omarchy_action(["omarchy-brightness-display", delta], f"Brightness updated ({delta})")
        return _action_result(ok, msg, state=read_system_state_sync())

    if action == "theme.set":
        name = str(params.get("name", "")).strip()
        valid_name = _validate_theme(name)
        if not valid_name:
            return _action_result(False, "Unknown Omarchy theme")
        ok, msg = _run_omarchy_action(["omarchy-theme-set", valid_name], f"Theme set to {valid_name}")
        return _action_result(ok, msg, state=read_system_state_sync())

    if action == "hyprland.workspace":
        try:
            ws_id = int(params.get("id", 1))
        except (TypeError, ValueError):
            return _action_result(False, "Invalid workspace id")
        if ws_id < 1 or ws_id > 20:
            return _action_result(False, "Workspace id out of range")
        ok, msg = _run_omarchy_action(["hyprctl", "dispatch", "workspace", str(ws_id)], f"Switched to workspace {ws_id}")
        return _action_result(ok, msg, state=read_system_state_sync())

    if action == "hyprland.launch_files":
        target_dir = str(params.get("path") or Path.home()).strip()
        resolved = Path(target_dir).expanduser()
        if not resolved.is_dir():
            resolved = Path.home()
        ok = _spawn_detached(["uwsm-app", "--", "nautilus", "--new-window", str(resolved)])
        return _action_result(ok, f"Opened Files at {resolved}" if ok else "Failed to launch Files")

    if action == "hyprland.launch_terminal":
        target_dir = str(params.get("path") or Path.home()).strip()
        resolved = Path(target_dir).expanduser()
        if not resolved.is_dir():
            resolved = Path.home()
        ok = _spawn_detached(["uwsm-app", "--", "xdg-terminal-exec", f"--working-directory={resolved}"])
        return _action_result(ok, f"Opened Terminal in {resolved}" if ok else "Failed to launch Terminal")

    if action == "hyprland.launch_browser":
        ok = _spawn_detached(["omarchy-launch-browser"])
        return _action_result(ok, "Launched browser on desktop" if ok else "Failed to launch browser")

    if action == "system.screensaver":
        ok = _spawn_detached(["omarchy-launch-screensaver"])
        return _action_result(ok, "Launched Omarchy screensaver" if ok else "Failed to launch screensaver")

    if action == "system.screenshot":
        ok = _spawn_detached(["omarchy-capture-screenshot", "smart"])
        return _action_result(ok, "Triggered Omarchy screenshot capture" if ok else "Failed to capture screenshot")

    if action == "security.sudo_prompt":
        duration = str(params.get("duration", "15")).strip()
        if duration not in {"15", "60", "1440", "permanent"}:
            return _action_result(False, "Duration must be 15, 60, 1440, or permanent")
        # Omarchy enforces an explicit local tty + sudo password confirmation boundary;
        # launch Omarchy's official presentation prompt on the desktop rather than bypassing sudo.
        ok = _spawn_detached([
            "omarchy-launch-floating-terminal-with-presentation",
            "omarchy-sudo-passwordless",
            duration,
        ])
        return _action_result(
            ok,
            f"Opened desktop confirmation prompt for passwordless sudo ({duration})"
            if ok
            else "Failed to open sudo prompt",
            state=read_system_state_sync(),
        )

    return _action_result(False, f"Unsupported control action: {action}")


async def execute_control_action(action: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    return await asyncio.to_thread(execute_control_action_sync, action, params)
