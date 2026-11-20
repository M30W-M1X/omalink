#!/usr/bin/env python3
"""Helper CLI for the OmaLink Omarchy top-bar plugin."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import sys
import time
from urllib import error, request
from urllib.parse import quote

DEFAULT_PORT = 7842
SERVICE_UNIT = "omalink-bridge.service"
LEGACY_SERVICE_UNIT = "omarchy-wizard-bridge.service"


def get_config_dir() -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "omalink"


def get_token_path() -> Path:
    return get_config_dir() / "token"


def get_cert_path() -> Path:
    return get_config_dir() / "cert.pem"


def read_token() -> str:
    p = get_token_path()
    if p.exists():
        return p.read_text(encoding="utf-8", errors="replace").strip()
    return ""


def read_cert_fingerprint() -> str:
    cert_path = get_cert_path()
    if not cert_path.is_file():
        return ""
    try:
        pem_lines = [
            ln.strip()
            for ln in cert_path.read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.startswith("-----")
        ]
        der = base64.b64decode("".join(pem_lines))
        return hashlib.sha256(der).hexdigest()
    except Exception:
        return ""


def build_local_ssl_context() -> ssl.SSLContext | None:
    cert_path = get_cert_path()
    if not cert_path.is_file():
        return None
    try:
        ctx = ssl.create_default_context(cafile=str(cert_path))
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        return ctx
    except Exception:
        return None


def detect_lan_ip() -> str:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        ip = sock.getsockname()[0]
        sock.close()
        return ip
    except OSError:
        return "127.0.0.1"


def _local_request(
    port: int,
    path: str,
    token: str,
    *,
    method: str = "GET",
    payload: dict | None = None,
    timeout: float = 1.5,
) -> tuple[dict | None, bool]:
    """Query the local loopback bridge, preferring strictly verified TLS over cert.pem."""
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    data: bytes | None = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")

    ctx = build_local_ssl_context()
    attempts: list[tuple[str, ssl.SSLContext | None]] = []
    if ctx is not None:
        attempts.append(("https", ctx))
    attempts.append(("http", None))

    for scheme, ssl_ctx in attempts:
        req = request.Request(
            f"{scheme}://127.0.0.1:{port}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with request.urlopen(req, timeout=timeout, context=ssl_ctx) as resp:
                raw = resp.read(256 * 1024).decode("utf-8", errors="replace")
                parsed = json.loads(raw)
                return (parsed if isinstance(parsed, dict) else None), (scheme == "https")
        except (error.URLError, error.HTTPError, TimeoutError, json.JSONDecodeError, OSError, ssl.SSLError):
            continue
    return None, False


def service_unit_path(name: str = SERVICE_UNIT) -> Path:
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "systemd" / "user" / name


def find_bridge_script() -> Path | None:
    candidates = [
        Path(__file__).resolve().parent.parent / "bridge" / "omarchy_wizard_bridge.py",
        Path.home() / ".local" / "share" / "omalink" / "bridge" / "omarchy_wizard_bridge.py",
        Path.home() / "Projects" / "omalink" / "bridge" / "omarchy_wizard_bridge.py",
        Path.home() / "Projects" / "omarchy_wizard" / "bridge" / "omarchy_wizard_bridge.py",
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


def ensure_service_installed(port: int) -> bool:
    """Create and enable omalink-bridge.service (TLS enabled by default)."""
    unit = service_unit_path(SERVICE_UNIT)
    if unit.exists():
        return True
    bridge_script = find_bridge_script()
    if not bridge_script or not shutil.which("systemctl"):
        return False
    unit.parent.mkdir(parents=True, exist_ok=True)
    unit.write_text(
        "[Unit]\n"
        "Description=OmaLink Companion Bridge (Android Continuity, Remote Desktop & AI Agents)\n"
        "After=network-online.target\n\n"
        "[Service]\n"
        "Type=simple\n"
        'Environment="PATH=%h/.local/share/mise/shims:%h/.local/share/mise/command-wrappers/bin:/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin:%h/.local/bin"\n'
        f"ExecStart=/usr/bin/python3 {bridge_script} --host 0.0.0.0 --port {port} --tls\n"
        "Restart=on-failure\n"
        "RestartSec=3\n\n"
        "[Install]\n"
        "WantedBy=default.target\n",
        encoding="utf-8",
    )
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=False, timeout=5)
    subprocess.run(["systemctl", "--user", "enable", SERVICE_UNIT], check=False, timeout=5)
    return True


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


def _private_qr_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    base = Path(runtime) / "omalink" if runtime else get_config_dir()
    base.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(base, 0o700)
    except OSError:
        pass
    return base / "pair-qr.png"


def generate_qr_png(pair_uri: str) -> str:
    """Write pairing QR PNG into a private 0700 directory (0600 file), piping secret via stdin."""
    if not pair_uri or not shutil.which("qrencode"):
        return ""
    out_path = _private_qr_path()
    try:
        proc = subprocess.run(
            ["qrencode", "-o", "-", "-s", "6", "-m", "2"],
            input=pair_uri.encode("utf-8"),
            capture_output=True,
            check=True,
            timeout=3,
        )
        fd = os.open(str(out_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            os.write(fd, proc.stdout)
        finally:
            os.close(fd)
        os.chmod(out_path, 0o600)
        return str(out_path)
    except Exception:
        return ""


def _build_local_pair_uri(port: int, token: str, use_tls: bool, tls_fp: str, ts_ip: str = "") -> str:
    lan_ip = detect_lan_ip()
    params = [
        f"host={quote(lan_ip)}",
        f"port={port}",
        f"token={quote(token)}",
        f"tls={'1' if use_tls else '0'}",
    ]
    if tls_fp:
        params.append(f"fp={quote(tls_fp)}")
    if ts_ip:
        params.append(f"ts={quote(ts_ip)}")
    return f"omalink://pair?{'&'.join(params)}"


def get_status(port: int) -> dict:
    token = read_token()
    lan_ip = detect_lan_ip()
    status_data, used_tls = _local_request(port, "/api/status", token)
    active = bool(status_data and status_data.get("ok"))
    is_tls = bool(status_data.get("tls", used_tls)) if status_data else used_tls
    scheme = "https" if is_tls else "http"
    pair_url = f"{scheme}://{lan_ip}:{port}"

    tasks: list[dict] = []
    if active:
        tasks_data, _ = _local_request(port, "/api/tasks", token)
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
    tls_fp = str(status_data.get("tls_fingerprint", "") or read_cert_fingerprint()) if status_data else ""
    ts_ip = str(status_data.get("tailscale_ip", "") or "") if status_data else ""
    qr_path = ""
    if active and token:
        pair_uri = _build_local_pair_uri(port, token, is_tls, tls_fp, ts_ip)
        qr_path = generate_qr_png(pair_uri)

    # Never emit raw secret token or pairUri containing token on stdout!
    return {
        "active": active,
        "tls": is_tls,
        "hasToken": bool(token),
        "pairUrl": pair_url,
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
    bridge_script = find_bridge_script()

    if state == "on":
        if shutil.which("systemctl"):
            if service_unit_path(LEGACY_SERVICE_UNIT).exists():
                subprocess.run(
                    ["systemctl", "--user", "disable", "--now", LEGACY_SERVICE_UNIT],
                    check=False,
                    timeout=5,
                )
            if ensure_service_installed(port):
                subprocess.run(["systemctl", "--user", "start", SERVICE_UNIT], check=False, timeout=5)
            elif bridge_script:
                subprocess.Popen(
                    [sys.executable, str(bridge_script), "--host", "0.0.0.0", "--port", str(port), "--tls"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
        elif bridge_script:
            subprocess.Popen(
                [sys.executable, str(bridge_script), "--host", "0.0.0.0", "--port", str(port), "--tls"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )

        for _ in range(12):
            snap = get_status(port)
            if snap.get("active"):
                return snap
            time.sleep(0.3)
        return get_status(port)

    if shutil.which("systemctl"):
        for unit in (SERVICE_UNIT, LEGACY_SERVICE_UNIT):
            if service_unit_path(unit).exists():
                subprocess.run(["systemctl", "--user", "stop", unit], check=False, timeout=5)
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

    token = read_token()

    if args.ring:
        res, _ = _local_request(
            args.port, "/api/continuity/ring", token, method="POST", payload={"duration": 12}, timeout=2.0
        )
        print(json.dumps({"action": "ring", "ok": bool(res and res.get("ok"))}))
        return

    if args.reply_id and args.reply_text:
        res, _ = _local_request(
            args.port,
            "/api/continuity/reply",
            token,
            method="POST",
            payload={"reply_id": args.reply_id, "text": args.reply_text},
            timeout=2.0,
        )
        print(json.dumps({"action": "reply", "ok": bool(res and res.get("ok"))}))
        return

    if args.copy_url:
        status_data, used_tls = _local_request(args.port, "/api/status", token)
        is_tls = bool(status_data.get("tls", used_tls)) if status_data else get_cert_path().is_file()
        scheme = "https" if is_tls else "http"
        ok = copy_to_clipboard(f"{scheme}://{detect_lan_ip()}:{args.port}")
        print(json.dumps({"copied": "url" if ok else ""}))
        return

    if args.copy_token:
        ok = copy_to_clipboard(token)
        print(json.dumps({"copied": "token" if ok else ""}))
        return

    if args.toggle:
        print(json.dumps(toggle_bridge(args.toggle, args.port)))
        return

    print(json.dumps(get_status(args.port)))


if __name__ == "__main__":
    main()
