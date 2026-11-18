#!/usr/bin/env python3
"""Helper CLI for the Omarchy Wizard bar badge plugin."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
from urllib import error, request

DEFAULT_PORT = 7842
SERVICE_UNIT = "omarchy-wizard-bridge.service"


def get_token_path() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "omarchy-wizard" / "token"


def read_token() -> str:
    p = get_token_path()
    if p.exists():
        return p.read_text(encoding="utf-8", errors="replace").strip()
    return ""


def detect_lan_ip() -> str:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
        return ip
    except OSError:
        return "127.0.0.1"


def fetch_json(url: str, token: str) -> dict | None:
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    req = request.Request(url, headers=headers, method="GET")
    try:
        with request.urlopen(req, timeout=1.2) as resp:
            raw = resp.read(256 * 1024).decode("utf-8", errors="replace")
            data = json.loads(raw)
            return data if isinstance(data, dict) else None
    except (error.URLError, error.HTTPError, TimeoutError, json.JSONDecodeError, OSError):
        return None


def service_installed() -> bool:
    unit = Path.home() / ".config" / "systemd" / "user" / SERVICE_UNIT
    return unit.exists()


def copy_to_clipboard(text: str) -> bool:
    if not text:
        return False
    for cmd in (["wl-copy"], ["xclip", "-selection", "clipboard"]):
        if shutil.which(cmd[0]):
            try:
                subprocess.run(cmd, input=text.encode("utf-8"), timeout=2, check=True)
                return True
            except Exception:
                pass
    return False


def post_json(url: str, token: str, payload: dict) -> dict | None:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(payload).encode("utf-8")
    req = request.Request(url, data=data, headers=headers, method="POST")
    try:
        with request.urlopen(req, timeout=2.0) as resp:
            raw = resp.read(128 * 1024).decode("utf-8", errors="replace")
            out = json.loads(raw)
            return out if isinstance(out, dict) else None
    except (error.URLError, error.HTTPError, TimeoutError, json.JSONDecodeError, OSError):
        return None


def generate_qr_png(pair_uri: str) -> str:
    if not pair_uri or not shutil.which("qrencode"):
        return ""
    out_path = Path(f"/tmp/omarchy-wizard-pair-qr-{os.getuid()}.png")
    try:
        subprocess.run(
            ["qrencode", "-o", str(out_path), "-s", "6", "-m", "2", pair_uri],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        return str(out_path)
    except Exception:
        return ""


def get_status(port: int) -> dict:
    token = read_token()
    lan_ip = detect_lan_ip()
    pair_url = f"http://{lan_ip}:{port}"
    status_data = fetch_json(f"http://127.0.0.1:{port}/api/status", token)
    active = bool(status_data and status_data.get("ok"))

    tasks: list[dict] = []
    if active:
        tasks_data = fetch_json(f"http://127.0.0.1:{port}/api/tasks", token)
        raw_tasks = tasks_data.get("tasks", []) if tasks_data else []
        if isinstance(raw_tasks, list):
            for item in raw_tasks[:4]:
                if not isinstance(item, dict):
                    continue
                tasks.append({
                    "id": str(item.get("id", ""))[:24],
                    "prompt": str(item.get("prompt", ""))[:120],
                    "agent": str(item.get("agent", "agy"))[:24],
                    "status": str(item.get("status", "running"))[:16],
                })

    phone = status_data.get("phone") if (status_data and isinstance(status_data.get("phone"), dict)) else {}
    replyable = status_data.get("replyable_notification") if status_data else None
    pair_uri = str(status_data.get("pair_uri", "")) if status_data else ""
    qr_path = generate_qr_png(pair_uri) if active and pair_uri else ""

    return {
        "active": active,
        "hasToken": bool(token),
        "pairUrl": pair_url,
        "pairUri": pair_uri,
        "qrPath": qr_path,
        "port": port,
        "defaultAgent": str(status_data.get("default_agent", "agy"))[:24] if status_data else "agy",
        "connectedClients": int(status_data.get("connected_clients", 0)) if status_data else 0,
        "runningTasks": int(status_data.get("running_tasks", 0)) if status_data else 0,
        "phoneName": str(phone.get("name", ""))[:32],
        "phoneBattery": phone.get("battery"),
        "phoneCharging": bool(phone.get("charging", False)),
        "replyable": replyable if isinstance(replyable, dict) else None,
        "recentTasks": tasks,
    }


def toggle_bridge(state: str, port: int) -> dict:
    bridge_script = Path(__file__).resolve().parent.parent / "bridge" / "omarchy_wizard_bridge.py"
    if not bridge_script.exists():
        bridge_script = Path.home() / "Projects" / "omarchy_wizard" / "bridge" / "omarchy_wizard_bridge.py"

    if state == "on":
        if service_installed() and shutil.which("systemctl"):
            subprocess.run(["systemctl", "--user", "start", SERVICE_UNIT], check=False, timeout=5)
        elif bridge_script.exists():
            subprocess.Popen(
                [sys.executable, str(bridge_script), "--host", "0.0.0.0", "--port", str(port)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
    else:
        if service_installed() and shutil.which("systemctl"):
            subprocess.run(["systemctl", "--user", "stop", SERVICE_UNIT], check=False, timeout=5)
        if shutil.which("pkill"):
            subprocess.run(["pkill", "-f", "omarchy_wizard_bridge.py"], check=False, timeout=3)

    return get_status(port)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--toggle", choices=["on", "off"], default=None)
    parser.add_argument("--copy-url", action="store_true")
    parser.add_argument("--copy-token", action="store_true")
    parser.add_argument("--ring", action="store_true")
    parser.add_argument("--reply-id", default="")
    parser.add_argument("--reply-text", default="")
    args = parser.parse_args()

    if args.ring:
        res = post_json(f"http://127.0.0.1:{args.port}/api/continuity/ring", read_token(), {"duration": 12})
        print(json.dumps({"action": "ring", "ok": bool(res and res.get("ok"))}))
        return

    if args.reply_id and args.reply_text:
        res = post_json(
            f"http://127.0.0.1:{args.port}/api/continuity/reply",
            read_token(),
            {"reply_id": args.reply_id, "text": args.reply_text},
        )
        print(json.dumps({"action": "reply", "ok": bool(res and res.get("ok"))}))
        return

    if args.copy_url:
        ok = copy_to_clipboard(f"http://{detect_lan_ip()}:{args.port}")
        print(json.dumps({"copied": "url" if ok else ""}))
        return

    if args.copy_token:
        ok = copy_to_clipboard(read_token())
        print(json.dumps({"copied": "token" if ok else ""}))
        return

    if args.toggle:
        print(json.dumps(toggle_bridge(args.toggle, args.port)))
        return

    print(json.dumps(get_status(args.port)))


if __name__ == "__main__":
    main()
