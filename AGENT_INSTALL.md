# AI Agent Install Guide — OmaLink (Omarchy Linux)

This guide is designed for **AI coding agents running directly inside Omarchy Linux** (such as Antigravity `agy`, Claude Code, Codex, OpenCode, Kimi, or Pi) to install, configure, and verify **OmaLink** autonomously with zero interactive prompts.

---

## Copy-Paste Prompt for Your AI Agent

Paste this into any AI agent running on your Omarchy desktop:

> Install **OmaLink** from `https://github.com/M30W-M1X/omalink` by following `AGENT_INSTALL.md` in that repo. Clone or update it, run `./install.sh --json`, verify `omalink-bridge.service` and `/api/ping`, validate and enable the `omalink.panel` top-bar plugin, run the bridge unit tests, check optional tools and firewall requirements (ask before running any `sudo` command), and give me the latest Android APK download link plus pairing instructions.

---

## Deterministic Agent Runbook

Execute these steps in order. Do **not** run `sudo` commands without asking the user first.

### Step 1 — Preflight Check

Verify Python 3.11+ and Omarchy environment:

```bash
python3 --version
command -v omarchy systemctl curl git || true
```

Requirements:
- **Python 3.11+** (the bridge uses pure Python standard library — **no `pip install` or venv required**).
- `systemd --user` active session.

### Step 2 — Run the Non-Interactive Installer (Immutable Commit & Verified Digest)

```bash
# Option A: Download release installer, verify exact SHA-256 digest (short-circuiting on mismatch), and run pinned to immutable 40-char commit SHA
curl -fsSLO https://github.com/M30W-M1X/omalink/releases/download/v3.7.0/install.sh && \
curl -fsSLO https://github.com/M30W-M1X/omalink/releases/download/v3.7.0/SHA256SUMS && \
echo "38016996361772f75df911fcfa23dd03c956f345d564f4ebae5b608540c70973  install.sh" | sha256sum -c - && \
grep '  install.sh$' SHA256SUMS | sha256sum -c - && \
bash install.sh --ref 7cad472b1e4429bfccec77c44a96bec02c410725 --json

# Option B: Install as an Omarchy Plugin Marketplace git plugin
omarchy plugin add https://github.com/M30W-M1X/omalink.git --enable --yes && \
~/.config/omarchy/plugins/omalink.panel/install.sh --no-plugin --no-restart-shell --json

# Option C: From a local checkout bound to the immutable 40-char commit SHA
git clone --no-checkout https://github.com/M30W-M1X/omalink.git ~/.local/share/omalink && \
git -C ~/.local/share/omalink fetch --depth 1 origin 7cad472b1e4429bfccec77c44a96bec02c410725 && \
git -C ~/.local/share/omalink checkout --detach 7cad472b1e4429bfccec77c44a96bec02c410725 && \
cd ~/.local/share/omalink && \
./install.sh --json
```

Optional flags:
- `--port 7842` — customize listen port (default `7842`).
- `--tls` — enable self-signed TLS encryption (`https://` + `wss://`) with SHA-256 fingerprint pinning.
- `--no-plugin` — skip installing the `omalink.panel` Omarchy top-bar widget.
- `--no-restart-shell` — skip restarting `omarchy-shell` (useful in headless SSH sessions).

The script outputs a structured JSON summary:
- `ok`: `true` when the bridge is running and `/api/ping` returns `200 OK`
- `bridge_url`: LAN URL (`http://<LAN_IP>:7842`)
- `tailscale_ip`: Tailscale IPv4 address if Tailscale is active
- `token_file`: `~/.config/omalink/token` (never echo the raw secret into public logs)
- `plugin_status`: `enabled` when `omalink.panel` passed `omarchy plugin validate`
- `missing_optional_tools`: list of optional binaries not currently installed

### Step 3 — Verify Service, Health & Unit Tests

Run the read-only health check and Python bridge test suite:

```bash
./install.sh --check --json
PYTHONPATH=bridge python3 -m unittest discover -s bridge -v
```

Expected results:
- `install.sh --check --json` exits `0` with `"ok": true`, `"service_state": "active"`, `"bridge_ping_ok": true`, and `"plugin_installed": true`.
- All bridge unit tests pass (`OK`).

### Step 4 — Check Optional Companion Tools & Firewall

Check `missing_optional_tools` from Step 2. All core features work without them, while specific extras use:

| Feature | Host Binary | Arch Package |
| --- | --- | --- |
| Remote Desktop screen capture | `grim` | `grim` |
| Remote Desktop / Trackpad typing | `wtype` | `wtype` |
| Universal Clipboard sync | `wl-copy` / `wl-paste` | `wl-clipboard` |
| Automatic LAN discovery (mDNS) | `avahi-publish` | `avahi` |
| Top-bar pairing QR code | `qrencode` | `qrencode` |
| Screen Recording toggle | `wf-recorder` | `wf-recorder` |
| Phone notification mirror | `notify-send` | `libnotify` |
| Audio volume / sink controls | `wpctl` | `wireplumber` |
| Display brightness | `brightnessctl` | `brightnessctl` |

If any desired package is missing or if UFW is active and blocking LAN port `7842/tcp`, **ask the user before running `sudo`**:

```bash
# Only after user confirmation:
sudo pacman -S --needed grim wtype wl-clipboard avahi qrencode
sudo ufw allow 7842/tcp
```

### Step 5 — Report Back to the User

Give the user a concise summary with:
1. **Service & Plugin status** (active bridge port, LAN / Tailscale IP, top-bar `omalink.panel` badge enabled).
2. **Android APK download & digest verification (`v3.7.0`)**: `https://github.com/M30W-M1X/omalink/releases/tag/v3.7.0` (download `app-release.apk` and `SHA256SUMS`, then verify with `grep '  app-release.apk$' SHA256SUMS | sha256sum -c -`).
3. **Pairing instructions**:
   - Click the **OmaLink icon in the Omarchy top bar** to display the live pairing QR code (or run `./install.sh --show-pairing` locally in a private terminal).
   - Scan with your phone camera (opens `omalink://pair?...`) or open **OmaLink** on Android -> **Sanctum** -> **Scan LAN (mDNS)**.
4. **Recommended Android toggles**:
   - **Notification Listener Access** (Continuity screen) — mirrors phone calls & texts to Omarchy with inline replies.
   - **Vitals & Agy Limits Shade** (Sanctum) — pins a silent live card of CPU/RAM/Temp + Agy usage quotas in the Android notification shade.
   - **Sync Omarchy Theme** (Sanctum) — matches the Android app colors live to `~/.config/omarchy/current/theme/colors.toml`.
   - **Mascot Avatar & App Icon** (Tools or Sanctum) — pick from 5 animated avatars and apply any as your Android Home Screen icon.

---

## Troubleshooting for Agents

| Symptom | Diagnosis & Fix |
| --- | --- |
| `bridge_ping_ok: false` | Run `journalctl --user -u omalink-bridge.service -n 40 --no-pager`. Check if another process holds port `7842` (`ss -tlnp \| grep 7842`) or re-run with `--port <alt>`. |
| Phone cannot reach LAN IP | Check `ufw status` (ask user to run `sudo ufw allow 7842/tcp`) or verify phone and host share the same Wi-Fi/Tailscale network. |
| Top-bar OmaLink icon missing or no QR code | Run `omarchy plugin validate ~/.config/omarchy/plugins/omalink.panel`, `omarchy plugin enable omalink.panel`, and `omarchy-restart-shell`. Ensure `qrencode` is installed. |
| Remote Desktop black screen or no input | Ensure Wayland session has `WAYLAND_DISPLAY` in systemd user env (`systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE`) and `grim` + `wtype` are installed. |
| Uninstall cleanly | Run `./install.sh --uninstall` (add `--purge` to also delete `~/.config/omalink`). |
