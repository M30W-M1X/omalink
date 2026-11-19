# OmaLink ✨

**Android Continuity, Remote Desktop, Trackpad, OS Control, and AI Agent companion for Omarchy Linux** — featuring a zero-dependency Python bridge, an Omarchy top-bar plugin (`omalink.panel`), live Omarchy theme syncing, silent notification-shade machine vitals + Agy limits, and 5 animated stylized mascots & switchable Android app icons.

> **Latest Android APK:** Download `app-release.apk` from [GitHub Releases](https://github.com/M30W-M1X/omalink/releases/latest).

---

## Screenshots

| Wizard Home & Mascot | Animated Avatars & App Icons | Companion Tools Menu | Omarchy Control Plane |
| :---: | :---: | :---: | :---: |
| <img src="docs/screenshots/01_home_wizard.png" width="200" alt="OmaLink Home screen with Arcane Agy mascot, labeled quick tiles, AI usage, and spell parameters" /> | <img src="docs/screenshots/08_avatar_picker.png" width="200" alt="Animated Anime Wizard mascot and switchable Android app icon picker" /> | <img src="docs/screenshots/02_tools_menu.png" width="200" alt="Material 3 Companion Tools bottom sheet" /> | <img src="docs/screenshots/04_control_plane.png" width="200" alt="Omarchy Control Plane with vitals, PipeWire audio, Spotify media controls, and output sinks" /> |

| Continuity & Notifications | Wireless Trackpad & Slides | Interactive Terminal | Sanctum & Pairing |
| :---: | :---: | :---: | :---: |
| <img src="docs/screenshots/03_continuity.png" width="200" alt="Omarchy Continuity with phone notification mirror and universal clipboard" /> | <img src="docs/screenshots/05_trackpad_remote.png" width="200" alt="Wireless Trackpad and Presentation Remote" /> | <img src="docs/screenshots/06_terminal.png" width="200" alt="Interactive PTY shell terminal with quick keys" /> | <img src="docs/screenshots/07_sanctum_settings.png" width="200" alt="Sanctum Settings with QR/mDNS pairing, TLS, theme sync, and vitals shade" /> |

---

## Quick Install

### Option 1 — Omarchy Plugin Marketplace (1 Command)

```bash
omarchy plugin add https://github.com/M30W-M1X/omalink.git --enable
```

Then click the **OmaLink** icon in your Omarchy top bar and click **Install & Start OmaLink Bridge** — it automatically sets up `omalink-bridge.service` and shows your live pairing QR code right in the top bar!

### Option 2 — Let Your Omarchy AI Agent Install It

Running **Antigravity (`agy`)**, **Claude Code**, **Codex**, **OpenCode**, or **Kimi** inside Omarchy? Paste this prompt into your AI agent:

> Install **OmaLink** from `https://github.com/M30W-M1X/omalink` by following `AGENT_INSTALL.md` in that repo. Clone or update it, run `./install.sh --json`, verify `omalink-bridge.service` and `/api/ping`, validate and enable the `omalink.panel` top-bar plugin, run the bridge unit tests, check optional tools and firewall requirements (ask before running any `sudo` command), and give me the latest Android APK download link plus pairing instructions.

See [AGENT_INSTALL.md](AGENT_INSTALL.md) for the full deterministic AI agent runbook and troubleshooting guide.

### Option 3 — One-Line Shell Installer

```bash
curl -fsSL https://raw.githubusercontent.com/M30W-M1X/omalink/master/install.sh | bash
```

Useful installer flags:
- `./install.sh --json` — machine-readable JSON output (used by AI agents)
- `./install.sh --check --json` — read-only health, service, plugin & tool diagnostics
- `./install.sh --tls` — enable self-signed TLS encryption (`https://` / `wss://`)
- `./install.sh --port 7842` — customize listen port (default `7842`)
- `./install.sh --show-pairing` — print the `omalink://pair` URI and terminal QR code
- `./install.sh --uninstall` — cleanly remove the systemd user service and top-bar plugin (add `--purge` to delete `~/.config/omalink`)

No Python pip dependencies are required — the bridge runs on **Python 3.11+ standard library only**.

---

## Pairing Your Android Phone

1. Download and install the latest `app-release.apk` from [GitHub Releases](https://github.com/M30W-M1X/omalink/releases/latest).
2. Click the **OmaLink badge** in your Omarchy top bar — it displays a live **QR code** by default (or run `./install.sh --show-pairing` in a local terminal).
3. Scan the QR code with your phone camera (opens `omalink://pair?...`) **or** open **OmaLink** -> **Sanctum** -> **Scan LAN (mDNS)** / **Paste Pair URI**.
4. If UFW is enabled on your host, allow the bridge port on your LAN:
   ```bash
   sudo ufw allow 7842/tcp
   ```

---

## Features

- **AI Agent Remote Controller & 5 Animated Mascots / App Icons**
  - Launch, monitor, stream, cancel, and resume sessions for `agy`, `claude`, `codex`, `kimi`, and `opencode`.
  - Live AI usage & quota overview right on the home screen + high-importance Android alerts when a task finishes or fails.
  - Animated `CustomPainter` wizard mascot (**Arcane Agy**) plus 4 switchable **animated illustrated avatars** (**Anime Wizard**, **Arcane Cat**, **Cyber-Mage**, **Astral Owl**) with floating/breathing motion, rotating arcane rune rings, starlight sparkles, and mood-reactive spells — any of which can also be applied live as your **Android Home Screen App Icon**!
- **Silent Notification-Shade Vitals & Agy Limits**
  - Optional silent, ongoing Android notification card pinned to your notification shade showing live **CPU, RAM, Temp, Uptime**, and **Agy usage limits** at a glance without ever chiming or vibrating.
- **Live Omarchy Theme Sync**
  - Watches `~/.config/omarchy/current/theme/colors.toml` and dynamically re-themes every screen and the `xterm` palette on your phone whenever you switch Omarchy themes (dark or light).
- **Omarchy Control Plane & Media**
  - Live vitals (CPU, RAM, disk, temperature), PipeWire volume/mute/mic/sink switcher, MPRIS media controls (Spotify & any MPRIS player), display brightness, Hyprland workspaces & windows, Omarchy toggles (Nightlight, Stay Awake, Top Bar, Animations, Screensaver, DND, Next Wallpaper), Bluetooth devices, Omarchy reminders, screenshot preview & screen recording toggle, system updates, app launchers, power actions, and temporary Passwordless Sudo (`omarchy-sudo-passwordless`).
- **Wayland Remote Desktop & Wireless Trackpad**
  - Low-latency Wayland screen stream (`grim`), pan/zoom, virtual mouse pointer (`zwlr_virtual_pointer_manager_v1`), and keyboard input (`wtype`).
  - Dedicated **Wireless Trackpad & Presentation Remote** (1-finger move/tap, 2-finger scroll, scroll strip, L/M/R clicks, and slide navigation).
- **Continuity (Phone ↔ Omarchy)**
  - Mirrors incoming Android notifications and calls onto your Hyprland desktop (`notify-send`) with **inline quick-reply** back to Android `RemoteInput`.
  - **Universal Clipboard** with automatic history sync and **Continue on Omarchy** Android Share Sheet target (share any link from Chrome/YouTube/Spotify to open it directly on Omarchy).
  - **Find My Phone** ringer from desktop + phone battery readout in the Omarchy top-bar plugin.
- **Interactive PTY Terminal & 2-Way File Explorer**
  - Full login shell over WebSockets (`/ws/terminal`) with `xterm` rendering and quick-key toolbar (`CTRL`, `ESC`, `TAB`, `^C`, `^D`, `^L`, arrows).
  - Browse directories, preview files, upload/download photos & files between phone and desktop, rename, Trash (`gio trash`), open on desktop (`xdg-open`), or hand paths straight to an AI agent.
- **Android System Integrations & Security**
  - Android **Quick Settings Tile**, **Home Screen Widget**, **Demo Familiar Mode**, and optional **TLS + SHA-256 certificate pinning**.

---

## Project Structure

- `manifest.json` — Root Omarchy Plugin Marketplace manifest (`omalink.panel`, validated with `omarchy plugin validate .`).
- `install.sh` — Idempotent non-interactive installer, health checker (`--check --json`), and uninstaller for Omarchy Linux.
- `AGENT_INSTALL.md` — Dedicated runbook & copy-paste prompt for AI agents inside Omarchy.
- `bridge/` — Pure Python 3.11+ HTTP + WebSocket server (`omarchy_wizard_bridge.py`), OS control (`omarchy_control.py`), Continuity (`omarchy_continuity.py`), Wayland Remote Desktop (`omarchy_desktop.py`), File Explorer (`omarchy_files.py`), PTY Terminal (`omarchy_pty.py`), and unit test suite (`test_bridge.py`).
- `omarchy-plugin/` — Omarchy top-bar status badge (`omalink.panel`, `Panel.qml`, `WizardIcon.qml`, `status.py`) with live pairing QR code, 1-click bridge auto-setup, connected devices, and quick replies.
- `android_app/` — Flutter Android app (`com.omarchy.omalink`) with Material 3 dynamic Omarchy theming, 5 animated avatars & switchable launcher icons, Quick Settings Tile, and Home Screen Widget.
- `.github/workflows/build.yml` — CI workflow running Python bridge tests, `flutter analyze`, `flutter test`, and publishing `app-release.apk` on version tags (`v*`).

---

## Development & Testing

### Bridge Tests (Python 3.11+)

```bash
PYTHONPATH=bridge python3 -m unittest discover -s bridge -v
```

### Flutter App Analysis, Tests & APK Build

```bash
cd android_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```
