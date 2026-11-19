#!/usr/bin/env bash
# OmaLink installer for humans and AI coding agents running inside Omarchy Linux.
# Supports Omarchy Plugin Marketplace installs, local repo installs, and curl-piped installs:
#   omarchy plugin add https://github.com/M30W-M1X/omalink.git --enable
#   curl -fsSL https://raw.githubusercontent.com/M30W-M1X/omalink/master/install.sh | bash
#   ./install.sh --json
#   ./install.sh --check --json
set -euo pipefail

REPO_URL="${OMALINK_REPO:-https://github.com/M30W-M1X/omalink.git}"
RELEASES_URL="https://github.com/M30W-M1X/omalink/releases/latest"
SERVICE_NAME="omalink-bridge.service"
LEGACY_SERVICE_NAME="omarchy-wizard-bridge.service"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME"
PLUGIN_ID="omalink.panel"
LEGACY_PLUGIN_ID="wizard.panel"
PLUGIN_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/omalink.panel"
LEGACY_PLUGIN_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/wizard-panel"
TOKEN_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/omalink/token"

INSTALL_DIR=""
PORT=7842
USE_TLS=0
INSTALL_PLUGIN=1
RESTART_SHELL=1
CHECK_ONLY=0
UNINSTALL=0
PURGE=0
JSON_OUT=0
SHOW_PAIRING=0

usage() {
  cat <<'EOF'
Usage: install.sh [OPTIONS]

Install, verify, or uninstall the OmaLink companion bridge service and Omarchy top-bar plugin.

Options:
  --dir PATH           Repository/install directory (auto-detected if run from repo;
                       otherwise defaults to ~/.local/share/omalink)
  --port PORT          Bridge listen port (default: 7842)
  --tls                Enable self-signed TLS encryption on the bridge service
  --no-plugin          Skip installing/enabling the Omarchy top-bar omalink.panel plugin
  --no-restart-shell   Skip restarting omarchy-shell after installing the plugin
  --check              Read-only health & dependency check (no changes made)
  --show-pairing       Print pairing deep link and ASCII QR code (contains secret token!)
  --json               Output machine-readable JSON summary (ideal for AI agents)
  --uninstall          Stop/disable the systemd service and remove the top-bar plugin
  --purge              With --uninstall, also remove ~/.config/omalink (token/certs)
  -h, --help           Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      INSTALL_DIR="${2:?--dir requires a path}"
      shift 2
      ;;
    --port)
      PORT="${2:?--port requires a number}"
      shift 2
      ;;
    --tls)
      USE_TLS=1
      shift
      ;;
    --no-plugin)
      INSTALL_PLUGIN=0
      shift
      ;;
    --no-restart-shell)
      RESTART_SHELL=0
      shift
      ;;
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --show-pairing)
      SHOW_PAIRING=1
      shift
      ;;
    --json)
      JSON_OUT=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --purge)
      PURGE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

log() {
  if [[ "$JSON_OUT" -eq 0 ]]; then
    printf '%s\n' "$*"
  fi
}

warn() {
  if [[ "$JSON_OUT" -eq 0 ]]; then
    printf 'WARN: %s\n' "$*" >&2
  fi
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -z "$INSTALL_DIR" ]]; then
  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/bridge/omarchy_wizard_bridge.py" ]]; then
    INSTALL_DIR="$SCRIPT_DIR"
  elif [[ -f "$PWD/bridge/omarchy_wizard_bridge.py" ]]; then
    INSTALL_DIR="$PWD"
  elif [[ -f "$HOME/Projects/omalink/bridge/omarchy_wizard_bridge.py" ]]; then
    INSTALL_DIR="$HOME/Projects/omalink"
  elif [[ -f "$HOME/Projects/omarchy_wizard/bridge/omarchy_wizard_bridge.py" ]]; then
    INSTALL_DIR="$HOME/Projects/omarchy_wizard"
  else
    INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omalink"
  fi
fi

detect_lan_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}' || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  printf '%s' "${ip:-127.0.0.1}"
}

detect_tailscale_ip() {
  if command -v tailscale >/dev/null 2>&1; then
    tailscale ip -4 2>/dev/null | head -n 1 || true
  fi
}

check_ping() {
  local scheme="http"
  local curl_flags=(-fsS --max-time 2)
  if [[ "$USE_TLS" -eq 1 ]]; then
    scheme="https"
    curl_flags+=(-k)
  fi
  curl "${curl_flags[@]}" "${scheme}://127.0.0.1:${PORT}/api/ping" >/dev/null 2>&1
}

collect_optional_tools() {
  local tools=(grim wtype wl-copy avahi-publish qrencode notify-send wpctl brightnessctl busctl gio wf-recorder)
  PRESENT_TOOLS=()
  MISSING_TOOLS=()
  for t in "${tools[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then
      PRESENT_TOOLS+=("$t")
    else
      MISSING_TOOLS+=("$t")
    fi
  done
}

# Handle uninstall
if [[ "$UNINSTALL" -eq 1 ]]; then
  log "Uninstalling OmaLink..."
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable --now "$LEGACY_SERVICE_NAME" 2>/dev/null || true
  fi
  rm -f "$SERVICE_FILE" "$SERVICE_DIR/$LEGACY_SERVICE_NAME"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
    omarchy plugin disable "$LEGACY_PLUGIN_ID" 2>/dev/null || true
  fi
  rm -rf "$PLUGIN_DEST" "$LEGACY_PLUGIN_DEST"
  if [[ "$PURGE" -eq 1 ]]; then
    rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/omalink"
  fi
  if [[ "$RESTART_SHELL" -eq 1 && -x "$(command -v omarchy-restart-shell 2>/dev/null || true)" ]]; then
    omarchy-restart-shell >/dev/null 2>&1 || true
  fi
  if [[ "$JSON_OUT" -eq 1 ]]; then
    python3 - <<PY
import json
print(json.dumps({
    "ok": True,
    "action": "uninstall",
    "purged_config": bool($PURGE),
    "service_removed": "$SERVICE_FILE",
    "plugin_removed": "$PLUGIN_DEST",
}, indent=2))
PY
  else
    log "OmaLink uninstalled."
    if [[ "$PURGE" -eq 0 ]]; then
      log "Note: Pairing token preserved at $TOKEN_FILE (pass --purge to remove)."
    fi
  fi
  exit 0
fi

# Verify Python 3.11+
command -v python3 >/dev/null 2>&1 || die "python3 is required (Python 3.11+)."
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
  die "Python 3.11+ is required (found: $(python3 --version 2>&1))."
fi

# Read-only health check mode
if [[ "$CHECK_ONLY" -eq 1 ]]; then
  SERVICE_STATE="unknown"
  if command -v systemctl >/dev/null 2>&1; then
    SERVICE_STATE="$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)"
  fi
  PING_OK=0
  if check_ping; then
    PING_OK=1
  fi
  PLUGIN_INSTALLED=0
  [[ -f "$PLUGIN_DEST/manifest.json" ]] && PLUGIN_INSTALLED=1
  TOKEN_EXISTS=0
  [[ -f "$TOKEN_FILE" ]] && TOKEN_EXISTS=1
  LAN_IP="$(detect_lan_ip)"
  TS_IP="$(detect_tailscale_ip)"
  collect_optional_tools

  if [[ "$JSON_OUT" -eq 1 ]]; then
    python3 - <<PY
import json
print(json.dumps({
    "ok": bool($PING_OK),
    "action": "check",
    "app": "OmaLink",
    "install_dir": "$INSTALL_DIR",
    "service_name": "$SERVICE_NAME",
    "service_state": "$SERVICE_STATE",
    "bridge_ping_ok": bool($PING_OK),
    "port": $PORT,
    "tls": bool($USE_TLS),
    "lan_ip": "$LAN_IP",
    "tailscale_ip": "$TS_IP" or None,
    "token_file": "$TOKEN_FILE",
    "token_exists": bool($TOKEN_EXISTS),
    "plugin_id": "$PLUGIN_ID",
    "plugin_installed": bool($PLUGIN_INSTALLED),
    "plugin_dir": "$PLUGIN_DEST",
    "present_optional_tools": "${PRESENT_TOOLS[*]:-}".split(),
    "missing_optional_tools": "${MISSING_TOOLS[*]:-}".split(),
    "releases_url": "$RELEASES_URL",
}, indent=2))
PY
  else
    log "OmaLink Health Check"
    log "  Install dir:    $INSTALL_DIR"
    log "  Service state:  $SERVICE_STATE ($SERVICE_NAME)"
    log "  Bridge ping:    $([[ "$PING_OK" -eq 1 ]] && echo OK || echo FAILED) (port $PORT)"
    log "  Token file:     $TOKEN_FILE ($([[ "$TOKEN_EXISTS" -eq 1 ]] && echo exists || echo missing))"
    log "  Top-bar plugin: $PLUGIN_DEST ($([[ "$PLUGIN_INSTALLED" -eq 1 ]] && echo installed || echo missing))"
    log "  LAN IP:         $LAN_IP${TS_IP:+ (Tailscale: $TS_IP)}"
    if [[ "${#MISSING_TOOLS[@]}" -gt 0 ]]; then
      log "  Optional tools missing: ${MISSING_TOOLS[*]}"
    fi
  fi
  [[ "$PING_OK" -eq 1 ]] || exit 1
  exit 0
fi

# 1. Clone or verify repository
if [[ ! -f "$INSTALL_DIR/bridge/omarchy_wizard_bridge.py" ]]; then
  command -v git >/dev/null 2>&1 || die "git is required to clone $REPO_URL into $INSTALL_DIR"
  log "Cloning OmaLink into $INSTALL_DIR..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
else
  log "Using OmaLink repository at $INSTALL_DIR"
fi

BRIDGE_SCRIPT="$INSTALL_DIR/bridge/omarchy_wizard_bridge.py"
[[ -f "$BRIDGE_SCRIPT" ]] || die "Bridge script not found at $BRIDGE_SCRIPT"

# 2. Migrate legacy systemd unit cleanly & start omalink-bridge.service
log "Configuring systemd user service ($SERVICE_FILE)..."
mkdir -p "$SERVICE_DIR"
command -v systemctl >/dev/null 2>&1 || die "systemctl is required to manage the bridge service."

if [[ -f "$SERVICE_DIR/$LEGACY_SERVICE_NAME" ]]; then
  systemctl --user disable --now "$LEGACY_SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "$SERVICE_DIR/$LEGACY_SERVICE_NAME"
fi

TLS_FLAG=""
if [[ "$USE_TLS" -eq 1 ]]; then
  TLS_FLAG=" --tls"
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=OmaLink Companion Bridge (Android Continuity, Remote Desktop & AI Agents)
After=network-online.target

[Service]
Type=simple
Environment="PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin:%h/.local/bin"
ExecStart=/usr/bin/python3 ${BRIDGE_SCRIPT} --host 0.0.0.0 --port ${PORT}${TLS_FLAG}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME" >/dev/null 2>&1
systemctl --user restart "$SERVICE_NAME"

PING_OK=0
for _ in $(seq 1 16); do
  if check_ping; then
    PING_OK=1
    break
  fi
  sleep 0.5
done

if [[ "$PING_OK" -ne 1 ]]; then
  warn "Bridge did not respond on port $PORT within 8s. Check: journalctl --user -u $SERVICE_NAME -n 40"
fi

if [[ -f "$TOKEN_FILE" ]]; then
  chmod 600 "$TOKEN_FILE" || true
fi

# 3. Install Omarchy top-bar plugin (omalink.panel) & retire legacy wizard.panel
PLUGIN_STATUS="skipped"
if [[ "$INSTALL_PLUGIN" -eq 1 && -f "$INSTALL_DIR/manifest.json" && -d "$INSTALL_DIR/omarchy-plugin" ]]; then
  log "Installing OmaLink top-bar plugin to $PLUGIN_DEST..."
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin disable "$LEGACY_PLUGIN_ID" >/dev/null 2>&1 || true
  fi
  rm -rf "$LEGACY_PLUGIN_DEST"

  mkdir -p "$PLUGIN_DEST"
  rm -rf "$PLUGIN_DEST"
  mkdir -p "$PLUGIN_DEST"
  cp "$INSTALL_DIR/manifest.json" "$PLUGIN_DEST/manifest.json"
  cp -r "$INSTALL_DIR/omarchy-plugin" "$PLUGIN_DEST/omarchy-plugin"
  chmod +x "$PLUGIN_DEST/omarchy-plugin/status.py" || true

  if command -v omarchy >/dev/null 2>&1; then
    if omarchy plugin validate "$PLUGIN_DEST" >/dev/null 2>&1; then
      if command -v omarchy-shell >/dev/null 2>&1; then
        omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
        for _ in $(seq 1 20); do
          if omarchy plugin list 2>/dev/null | grep -q "$PLUGIN_ID"; then
            break
          fi
          sleep 0.1
        done
      fi
      omarchy plugin enable "$PLUGIN_ID" --before omarchy.agents >/dev/null 2>&1 \
        || omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 \
        || true
      PLUGIN_STATUS="enabled"
    else
      warn "omarchy plugin validate reported warnings for $PLUGIN_DEST"
      PLUGIN_STATUS="installed_unvalidated"
    fi
  else
    PLUGIN_STATUS="copied_no_omarchy_cli"
  fi

  if [[ "$RESTART_SHELL" -eq 1 ]]; then
    if command -v omarchy-restart-shell >/dev/null 2>&1; then
      log "Restarting Omarchy shell so the top-bar OmaLink badge appears..."
      omarchy-restart-shell >/dev/null 2>&1 || true
    elif command -v omarchy >/dev/null 2>&1; then
      omarchy restart shell >/dev/null 2>&1 || true
    fi
  fi
fi

# 4. Collect diagnostics
LAN_IP="$(detect_lan_ip)"
TS_IP="$(detect_tailscale_ip)"
SCHEME="http"
[[ "$USE_TLS" -eq 1 ]] && SCHEME="https"
SERVICE_STATE="$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || echo unknown)"
collect_optional_tools

if [[ "$JSON_OUT" -eq 1 ]]; then
  python3 - <<PY
import json
payload = {
    "ok": bool($PING_OK),
    "action": "install",
    "app": "OmaLink",
    "install_dir": "$INSTALL_DIR",
    "service_name": "$SERVICE_NAME",
    "service_file": "$SERVICE_FILE",
    "service_state": "$SERVICE_STATE",
    "bridge_ping_ok": bool($PING_OK),
    "bridge_url": f"$SCHEME://$LAN_IP:$PORT",
    "port": $PORT,
    "tls": bool($USE_TLS),
    "lan_ip": "$LAN_IP",
    "tailscale_ip": "$TS_IP" or None,
    "token_file": "$TOKEN_FILE",
    "plugin_id": "$PLUGIN_ID",
    "plugin_status": "$PLUGIN_STATUS",
    "plugin_dir": "$PLUGIN_DEST",
    "present_optional_tools": "${PRESENT_TOOLS[*]:-}".split(),
    "missing_optional_tools": "${MISSING_TOOLS[*]:-}".split(),
    "releases_url": "$RELEASES_URL",
    "firewall_hint": f"sudo ufw allow $PORT/tcp",
}
print(json.dumps(payload, indent=2))
PY
  [[ "$PING_OK" -eq 1 ]] || exit 1
  exit 0
fi

log ""
log "OmaLink installation complete!"
log "  Bridge URL:     ${SCHEME}://${LAN_IP}:${PORT}"
if [[ -n "$TS_IP" ]]; then
  log "  Tailscale URL:  ${SCHEME}://${TS_IP}:${PORT}"
fi
log "  Service state:  ${SERVICE_STATE} (${SERVICE_NAME})"
log "  Bridge health:  $([[ "$PING_OK" -eq 1 ]] && echo 'OK (/api/ping)' || echo 'FAILED')"
log "  Top-bar badge:  ${PLUGIN_STATUS} (${PLUGIN_ID} -> ${PLUGIN_DEST})"
log "  Token path:     ${TOKEN_FILE}"
log "  Android APK:    ${RELEASES_URL}"
log ""
log "Next steps:"
log "  1. Download and install the latest app-release.apk on Android from:"
log "     ${RELEASES_URL}"
log "  2. Click the OmaLink icon in your Omarchy top bar to scan the live pairing QR code."
log "  3. Or open OmaLink on Android -> Sanctum -> Scan LAN (mDNS) / Paste Pair URI."
log "  4. If UFW firewall blocks LAN traffic, run: sudo ufw allow ${PORT}/tcp"

if [[ "${#MISSING_TOOLS[@]}" -gt 0 ]]; then
  log ""
  log "Optional host tools not found (some companion features use these):"
  log "  ${MISSING_TOOLS[*]}"
  log "  Tip: grim + wtype (Remote Desktop/Trackpad), wl-copy (Clipboard Sync),"
  log "       avahi-publish (LAN Auto-Discovery), qrencode (Top-bar QR), wf-recorder (Screen Record)."
fi

if [[ "$SHOW_PAIRING" -eq 1 && -f "$TOKEN_FILE" ]]; then
  TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
  HOST_NAME="$(hostname)"
  PAIR_URI="omalink://pair?host=${LAN_IP}&port=${PORT}&token=${TOKEN}&name=${HOST_NAME}&tls=${USE_TLS}"
  log ""
  log "Pairing URI (keep private):"
  log "  ${PAIR_URI}"
  if command -v qrencode >/dev/null 2>&1; then
    log ""
    qrencode -t ANSIUTF8 "$PAIR_URI"
  fi
fi

[[ "$PING_OK" -eq 1 ]] || exit 1
