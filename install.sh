#!/usr/bin/env bash
# OmaLink installer for humans and AI coding agents running inside Omarchy Linux.
# Defaults to an immutable 40-char commit SHA (v3.7.0), verifies runtime file SHA-256 digests,
# and enables TLS 1.2+ encryption with SHA-256 certificate pinning.
#
# Recommended usage (download from release with SHA256SUMS, verify digest, then run):
#   curl -fsSLO https://github.com/M30W-M1X/omalink/releases/download/v3.7.0/install.sh
#   curl -fsSLO https://github.com/M30W-M1X/omalink/releases/download/v3.7.0/SHA256SUMS
#   grep '  install.sh$' SHA256SUMS | sha256sum -c -
#   less install.sh
#   bash install.sh --ref adfceb68b87fc9e7def2ddf40269b011381dc789
#
# Or from a local checkout (such as `omarchy plugin add`):
#   ./install.sh --json
#   ./install.sh --check --json
set -euo pipefail

RELEASE_TAG="v3.7.0"
DEFAULT_COMMIT_SHA="adfceb68b87fc9e7def2ddf40269b011381dc789"
DEFAULT_REF="$DEFAULT_COMMIT_SHA"
REPO_URL="${OMALINK_REPO:-https://github.com/M30W-M1X/omalink.git}"
RELEASES_URL="https://github.com/M30W-M1X/omalink/releases/tag/${RELEASE_TAG}"
SERVICE_NAME="omalink-bridge.service"
LEGACY_SERVICE_NAME="omarchy-wizard-bridge.service"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME"
PLUGIN_ID="omalink.panel"
LEGACY_PLUGIN_ID="wizard.panel"
PLUGIN_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/omalink.panel"
LEGACY_PLUGIN_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/wizard-panel"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omalink"
TOKEN_FILE="$CONFIG_DIR/token"
CERT_FILE="$CONFIG_DIR/cert.pem"

INSTALL_DIR=""
GIT_REF="${OMALINK_REF:-$DEFAULT_REF}"
ALLOW_MUTABLE=0
PORT=7842
USE_TLS=1
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
  --ref COMMIT_SHA     Immutable 40-char commit SHA (or verified release tag v3.7.0)
                       to install when cloning remotely
                       (default: adfceb68b87fc9e7def2ddf40269b011381dc789)
  --allow-mutable      Explicitly allow a mutable git ref or locally modified files (not recommended)
  --port PORT          Bridge listen port (default: 7842)
  --tls                Enable self-signed TLS encryption on the bridge service (default)
  --insecure-http      Disable TLS and use plaintext HTTP (not recommended)
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
    --ref)
      GIT_REF="${2:?--ref requires a tag or commit SHA}"
      shift 2
      ;;
    --allow-mutable)
      ALLOW_MUTABLE=1
      shift
      ;;
    --port)
      PORT="${2:?--port requires a number}"
      shift 2
      ;;
    --tls)
      USE_TLS=1
      shift
      ;;
    --insecure-http)
      USE_TLS=0
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

validate_ref() {
  local ref="$1"
  if [[ "$ALLOW_MUTABLE" -eq 1 ]]; then
    return 0
  fi
  if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    return 0
  fi
  if [[ "$ref" == "$RELEASE_TAG" ]]; then
    return 0
  fi
  die "Refusing unverified or mutable ref '$ref'. Bind to an immutable 40-char commit SHA (e.g. --ref $DEFAULT_COMMIT_SHA) or verified release $RELEASE_TAG (or pass --allow-mutable)."
}

verify_runtime_digests() {
  local target_dir="$1"
  if [[ "$ALLOW_MUTABLE" -eq 1 ]]; then
    return 0
  fi
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required to verify runtime artifact integrity."
  if ! (
    cd "$target_dir" && sha256sum -c --status <<'EOF_SHA256'
a88ee7d5b2e4ea936f0d83ae25ddc33e7a75799734a497e524ac317ee06e1ae1  manifest.json
7070ad8428f54f37f49b27043a4fd9934a632108550659b7afc6fd430f8d8723  bridge/omarchy_wizard_bridge.py
08204f0acf2d2c87221fb12ce76223b4d8fdb8cf1df95ec054a0bee1b8d46b27  bridge/omarchy_control.py
2b2f274dc7b0e7d94f58ac61aa578672def4b23f7a06ad20035f4b1aa302da46  bridge/omarchy_continuity.py
2c708c3e1fc9d1cbd3930fbf8cff55f15c5ca96096e3f2cade152ce641dbad35  bridge/omarchy_desktop.py
b7dd6b9958741d23d8e5e4c65db0a7311c51779e61b42c1a06a565c32189e749  bridge/omarchy_files.py
116a0231c0ea8edf2d19a6150b18fdb19aed83c34556e823b738b73c45bd0fca  bridge/omarchy_pty.py
66d185f29f85f98a439350b895e46b9a1bc8d16fae195eddcac47e7faabc9ceb  bridge/omarchy_sessions.py
ee4c6d273253f481bae0514cb1432db7838b7e2e1bcc0d268cb99a7973eb3c83  omarchy-plugin/status.py
e5b1941607c4d3c9c9bf0220e0df651dcbbfdce808272d30a06303ed43cb562a  omarchy-plugin/Panel.qml
8be84d43e8dcd6e935e0707dfbc07f65f0e9abcd08cc3bb04a53611c0dcd27c2  omarchy-plugin/WizardIcon.qml
EOF_SHA256
  ); then
    die "Runtime SHA-256 digest verification failed in $target_dir for release $RELEASE_TAG ($DEFAULT_COMMIT_SHA). Pass --allow-mutable only if testing local modifications."
  fi
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
  if [[ "$USE_TLS" -eq 1 && -f "$CERT_FILE" ]]; then
    curl -fsS --max-time 2 --cacert "$CERT_FILE" "https://127.0.0.1:${PORT}/api/ping" >/dev/null 2>&1
    return $?
  fi
  if [[ "$USE_TLS" -eq 0 ]]; then
    curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/api/ping" >/dev/null 2>&1
    return $?
  fi
  return 1
}

read_cert_fingerprint() {
  if [[ ! -f "$CERT_FILE" ]]; then
    return 0
  fi
  python3 - "$CERT_FILE" <<'PY'
import base64, hashlib, sys
from pathlib import Path
lines = [l.strip() for l in Path(sys.argv[1]).read_text().splitlines() if l.strip() and not l.startswith("-----")]
print(hashlib.sha256(base64.b64decode("".join(lines))).hexdigest())
PY
}

collect_optional_tools() {
  local tools=(openssl grim wtype wl-copy avahi-publish qrencode notify-send wpctl brightnessctl busctl gio wf-recorder)
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
    rm -rf "$CONFIG_DIR"
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
      log "Note: Pairing credentials preserved in $CONFIG_DIR (pass --purge to remove)."
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
  TLS_FP="$(read_cert_fingerprint)"
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
    "tls_fingerprint": "$TLS_FP" or None,
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
    log "  Bridge ping:    $([[ "$PING_OK" -eq 1 ]] && echo OK || echo FAILED) (port $PORT, TLS=$USE_TLS)"
    log "  Token file:     $TOKEN_FILE ($([[ "$TOKEN_EXISTS" -eq 1 ]] && echo exists || echo missing))"
    if [[ -n "$TLS_FP" ]]; then
      log "  TLS SHA-256:    $TLS_FP"
    fi
    log "  Top-bar plugin: $PLUGIN_DEST ($([[ "$PLUGIN_INSTALLED" -eq 1 ]] && echo installed || echo missing))"
    log "  LAN IP:         $LAN_IP${TS_IP:+ (Tailscale: $TS_IP)}"
    if [[ "${#MISSING_TOOLS[@]}" -gt 0 ]]; then
      log "  Optional tools missing: ${MISSING_TOOLS[*]}"
    fi
  fi
  [[ "$PING_OK" -eq 1 ]] || exit 1
  exit 0
fi

# 1. Clone pinned immutable ref or verify local checkout
if [[ ! -f "$INSTALL_DIR/bridge/omarchy_wizard_bridge.py" ]]; then
  command -v git >/dev/null 2>&1 || die "git is required to clone $REPO_URL into $INSTALL_DIR"
  validate_ref "$GIT_REF"
  log "Cloning OmaLink ($GIT_REF) into $INSTALL_DIR..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  if [[ "$GIT_REF" =~ ^[0-9a-fA-F]{40}$ ]]; then
    git clone --no-checkout "$REPO_URL" "$INSTALL_DIR"
    git -C "$INSTALL_DIR" fetch --depth 1 origin "$GIT_REF"
    git -C "$INSTALL_DIR" checkout --detach "$GIT_REF"
  else
    git clone --depth 1 --branch "$GIT_REF" "$REPO_URL" "$INSTALL_DIR"
    git -C "$INSTALL_DIR" checkout --detach HEAD >/dev/null 2>&1 || true
  fi
else
  log "Using local OmaLink checkout at $INSTALL_DIR"
fi

BRIDGE_SCRIPT="$INSTALL_DIR/bridge/omarchy_wizard_bridge.py"
[[ -f "$BRIDGE_SCRIPT" ]] || die "Bridge script not found at $BRIDGE_SCRIPT"
verify_runtime_digests "$INSTALL_DIR"

# 2. Migrate legacy systemd unit cleanly & start omalink-bridge.service (TLS by default)
log "Configuring systemd user service ($SERVICE_FILE)..."
mkdir -p "$SERVICE_DIR"
command -v systemctl >/dev/null 2>&1 || die "systemctl is required to manage the bridge service."

if [[ -f "$SERVICE_DIR/$LEGACY_SERVICE_NAME" ]]; then
  systemctl --user disable --now "$LEGACY_SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "$SERVICE_DIR/$LEGACY_SERVICE_NAME"
fi

TLS_FLAG="--tls"
if [[ "$USE_TLS" -eq 0 ]]; then
  TLS_FLAG="--insecure-http"
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=OmaLink Companion Bridge (Android Continuity, Remote Desktop & AI Agents)
After=network-online.target

[Service]
Type=simple
Environment="PATH=%h/.local/share/mise/shims:%h/.local/share/mise/command-wrappers/bin:/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin:%h/.local/bin"
ExecStart=/usr/bin/python3 ${BRIDGE_SCRIPT} --host 0.0.0.0 --port ${PORT} ${TLS_FLAG}
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

if [[ -d "$CONFIG_DIR" ]]; then
  chmod 700 "$CONFIG_DIR" || true
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
TLS_FP="$(read_cert_fingerprint)"
SCHEME="https"
[[ "$USE_TLS" -eq 0 ]] && SCHEME="http"
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
    "tls_fingerprint": "$TLS_FP" or None,
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
if [[ -n "$TLS_FP" ]]; then
  log "  TLS SHA-256:    ${TLS_FP}"
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
log "  3. Confirm the host & TLS fingerprint dialog on your phone."
log "  4. If UFW firewall blocks LAN traffic, run: sudo ufw allow ${PORT}/tcp"

if [[ "${#MISSING_TOOLS[@]}" -gt 0 ]]; then
  log ""
  log "Optional host tools not found (some companion features use these):"
  log "  ${MISSING_TOOLS[*]}"
fi

if [[ "$SHOW_PAIRING" -eq 1 && -f "$TOKEN_FILE" ]]; then
  TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
  PAIR_URI="omalink://pair?host=${LAN_IP}&port=${PORT}&token=${TOKEN}&tls=${USE_TLS}${TLS_FP:+&fp=${TLS_FP}}${TS_IP:+&ts=${TS_IP}}"
  log ""
  log "Pairing URI (keep private):"
  log "  ${PAIR_URI}"
  if command -v qrencode >/dev/null 2>&1; then
    log ""
    printf '%s' "$PAIR_URI" | qrencode -t ANSIUTF8
  fi
fi

[[ "$PING_OK" -eq 1 ]] || exit 1
