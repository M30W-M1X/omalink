# AGENTS.md — AI Coding Agent Guide for OmaLink

This file provides architectural context, build/test commands, marketplace constraints, and security invariants for AI coding agents (**Antigravity `agy`**, **Claude Code**, **Codex**, **OpenCode**, **Kimi**) developing or maintaining the **OmaLink** repository.

> **Looking to install OmaLink on an Omarchy Linux desktop?** Follow [AGENT_INSTALL.md](AGENT_INSTALL.md) instead.

---

## 1. Repository Architecture

- **[manifest.json](manifest.json)** — Root Omarchy Plugin Marketplace manifest (`id: "omalink.panel"`, `entryPoints.barWidget: "omarchy-plugin/Panel.qml"`).
- **[bridge/](bridge/)** — Pure Python 3.11+ standard-library HTTP & WebSocket companion bridge (zero `pip` dependencies):
  - `omarchy_wizard_bridge.py` — Main asyncio HTTP/WebSocket server, TLS 1.2+ self-signed cert generation & SHA-256 fingerprint pinning, 256-bit bearer token auth, rate limiter, mDNS publisher, and AI task runner.
  - `omarchy_sessions.py` — Live AI agent session discovery (`agy` & `claude`), transcript/tool-call parser, `ask_question` detector, interactive reply sender (`agy --chat --resume` / `claude --resume` or Hyprland window `wtype`), and session closer.
  - `omarchy_control.py` — Omarchy Linux vitals, PipeWire audio/sinks, MPRIS media players, brightness, Hyprland workspaces/windows, Omarchy toggles, Bluetooth, reminders, screenshots/recordings, and live theme palette reader (`~/.config/omarchy/current/theme/colors.toml`).
  - `omarchy_continuity.py` — Phone-to-desktop notification mirroring (`notify-send` with inline reply actions), universal clipboard (`wl-copy` / `wl-paste` + Omarchy clipboard history), URI/text handoff, and phone device state.
  - `omarchy_desktop.py` — Low-latency Wayland remote desktop frame capture (`grim`) and virtual pointer/keyboard input (`wtype`).
  - `omarchy_files.py` — Two-way file explorer, preview, upload/download, rename, and trash (`gio trash`).
  - `omarchy_pty.py` — Interactive login PTY shell streamed over `/ws/terminal`.
  - `test_bridge.py` — Comprehensive Python `unittest` suite covering all bridge endpoints and security invariants.
- **[omarchy-plugin/](omarchy-plugin/)** — Omarchy top-bar Quickshell plugin (`omalink.panel`):
  - `Panel.qml` — Top-bar dropdown with the **Connected Device** hero card (10-segment battery gauge, `Ring Phone`, `Send Clip`, inline notification quick-reply bubble), recent spells, and compact **Bridge & Pairing** footer with auto-hiding QR code.
  - `WizardIcon.qml` — Custom vector wizard hat icon with corner activity/connection dot.
  - `status.py` — Local status & action helper called by `Panel.qml` over verified loopback TLS (`https://127.0.0.1:7842`).
- **[android_app/](android_app/)** — Flutter Android application (`io.github.m30w_m1x.omalink`):
  - `lib/main.dart` — App entry point, navigation shell, foreground/background lifecycle management, and request-bound pairing/share confirmation dialogs.
  - `lib/services/bridge_client.dart` — HTTP + WebSocket client, background battery throttling, pairing/share state machine, and continuity listeners.
  - `lib/services/tls_overrides.dart` — Strict constant-time 64-hex SHA-256 certificate pinning for self-signed bridge TLS certificates.
  - `lib/screens/` — `wizard_home_screen.dart`, `sessions_screen.dart`, `control_plane_screen.dart`, `continuity_screen.dart`, `remote_desktop_screen.dart`, `trackpad_screen.dart`, `terminal_screen.dart`, `file_explorer_screen.dart`, `settings_screen.dart`, `task_detail_screen.dart`.
  - `lib/widgets/` — `arcane_wizard_mascot.dart` (5 animated avatars + lifecycle ticker pausing) and `avatar_picker_sheet.dart` (live Android `<activity-alias>` launcher icon switching).
  - `android/app/src/main/kotlin/io/github/m30w_m1x/omalink/` — Native Android foreground service (`OmaLinkBackgroundService.kt`), `NotificationRelayService.kt`, `QuickSpellTileService.kt`, `WizardWidgetProvider.kt`, and `MainActivity.kt`.
- **[install.sh](install.sh)** — Idempotent installer, runtime SHA-256 digest verifier (`verify_runtime_digests`), health checker (`--check --json`), and uninstaller.

---

## 2. Mandatory Omarchy Marketplace Rules

1. **Single Root `manifest.json` Only:**
   - The Omarchy Plugin Marketplace validator requires **exactly one** `manifest.json` in the repository root (`/manifest.json`).
   - **Never** add a duplicate `omarchy-plugin/manifest.json` or any other `manifest.json` file.
2. **Zero Symlinks:**
   - Do not commit symlinks anywhere in the repository (`find . -maxdepth 3 -type l` must be empty).
3. **Validate Before Committing:**
   ```bash
   omarchy plugin validate .
   ```

---

## 3. Security Invariants (Do Not Regress)

- **Request-Bound Confirmations (Android):**
  - `confirmPendingPairing(PendingPairingRequest expected)` and `confirmPendingShare(PendingShareRequest expected)` in `android_app/lib/services/bridge_client.dart` and `android_app/lib/main.dart` must bind to the exact displayed request (`identical(current, expected) && current.matches(expected)`) and discard the pending item (`= null`) if it changes while the dialog is open.
- **Fail-Closed Loopback TLS (`omarchy-plugin/status.py`):**
  - `_local_request(...)` must require a verified local `ssl.SSLContext` (`~/.config/omalink/cert.pem`, TLS 1.2+) and connect exclusively over `https://127.0.0.1:{port}`. Never add a plaintext `http://` fallback when sending the bearer token.
- **Bridge Authentication & Transport:**
  - Always check the `Authorization: Bearer <token>` header using `hmac.compare_digest` **before** reading any HTTP request body. Never accept `?token=` in query strings.
  - Keep rate limiting (including IPv6 `/64` prefix normalization) and the 2 MB WebSocket frame cap enabled.
  - Keep symlink no-follow (`follow_symlinks=False` / `is_symlink()`) and the sensitive path blocklist (`~/.config/omalink`, `~/.ssh`, `~/.gnupg`, etc.) in `bridge/omarchy_files.py`.
  - Keep URI scheme allowlisting (`https`, `http`, `mailto`, `spotify`) in `bridge/omarchy_continuity.py`.
- **Per-Connection Clipboard Scoping (`bridge/omarchy_wizard_bridge.py`, `omarchy-plugin/Panel.qml`, `omarchy-plugin/status.py`, `android_app/lib/services/bridge_client.dart`):**
  - Each `WebSocketClient` gets a unique 128-bit `client_id` (`secrets.token_urlsafe(16)`), stored in memory only (never persisted to `phone_device.json`) and cleared immediately when disconnected.
  - `POST /api/continuity/push-clipboard` must require a matching `target_client_id` (returning `409 Conflict` on switch/mismatch even when two phones share the same model/display name), must return `400 Bad Request` when the current clipboard is empty (never falling back to clipboard history), and must send only `{"text": text}` (no `history` key).
  - Android `continuity.clipboard_update` must write to the system clipboard **only** when `_settings.autoSyncClipboard` is enabled.
- **Fail-Closed Copyable Commands & Installer Digest Verification (`install.sh`, `README.md`, `AGENT_INSTALL.md`):**
  - Every copyable multi-line command block that downloads, verifies `sha256sum -c -`, and runs `install.sh` MUST chain commands with `&& \` so a checksum mismatch immediately halts execution in interactive shells.
  - `install.sh` embeds the SHA-256 digests of all 11 runtime files (`manifest.json`, `bridge/*.py` excluding `test_bridge.py`, and `omarchy-plugin/*`) in `verify_runtime_digests()`.
  - **Whenever you edit any of those 11 runtime files**, recompute their SHA-256 digests and update the `EOF_SHA256` block in `install.sh`:
    ```bash
    sha256sum manifest.json bridge/omarchy_wizard_bridge.py bridge/omarchy_control.py \
      bridge/omarchy_continuity.py bridge/omarchy_desktop.py bridge/omarchy_files.py \
      bridge/omarchy_pty.py bridge/omarchy_sessions.py omarchy-plugin/status.py \
      omarchy-plugin/Panel.qml omarchy-plugin/WizardIcon.qml
    ```

---

## 4. Build, Test & Local Sync Workflow

Run all three checks before committing or tagging a release:

```bash
# 1. Validate Omarchy plugin layout & manifest
omarchy plugin validate .

# 2. Run Python bridge & status helper unit tests (16 tests)
PYTHONPATH=bridge python3 -m unittest discover -s bridge -v

# 3. Run Flutter analyzer & unit/widget tests
cd android_app
flutter analyze
flutter test
cd ..
```

To deploy and test your changes live on the local Omarchy desktop (`omalink-bridge.service` + `~/.config/omarchy/plugins/omalink.panel`):

```bash
./install.sh --json
./install.sh --check --json
```

---

## 5. Aligned Release & Digest Checklist (Mandatory for Omarchy Plugin Releases)

Never leave `README.md`, `AGENT_INSTALL.md`, `install.sh`, `manifest.json`, `android_app/pubspec.yaml`, or GitHub Release assets pointing to different versions, tags, or digests. Whenever releasing a new Omarchy plugin version (`vX.Y.Z`)—or whenever `install.sh` or any of the 11 runtime files change—follow this exact two-commit release procedure:

1. **Commit 1 — Runtime & Version Bump (Produces the Immutable 40-Char Commit SHA):**
   - Bump `version` in `manifest.json` (`"X.Y.Z"`) and `version` in `android_app/pubspec.yaml` (`X.Y.Z+N`).
   - Run all validation and test suites (`omarchy plugin validate .`, Python bridge tests, `flutter analyze`, `flutter test`).
   - Commit all code/runtime changes and record the resulting immutable 40-character commit SHA:
     ```bash
     RUNTIME_SHA="$(git rev-parse HEAD)"
     ```
2. **Commit 2 — Installer, Docs & Digest Alignment:**
   - Recompute the SHA-256 digests of all 11 runtime files (`manifest.json`, `bridge/*.py` excluding `test_bridge.py`, `omarchy-plugin/*`) and update the `EOF_SHA256` block in `install.sh`.
   - Set `RELEASE_TAG="vX.Y.Z"` and `DEFAULT_COMMIT_SHA="$RUNTIME_SHA"` in `install.sh` (and verify `./install.sh --no-restart-shell --json` passes digest verification).
   - Compute the exact SHA-256 digest of `install.sh`:
     ```bash
     sha256sum install.sh
     ```
   - Update `README.md` and `AGENT_INSTALL.md` so **every** release link, `--ref <40-char-commit-sha>`, and `echo "<INSTALL_SH_SHA256>  install.sh" | sha256sum -c -` matches `vX.Y.Z`, `$RUNTIME_SHA`, and the exact `install.sh` SHA-256 digest (chained with `&& \`).
   - For `app-release.apk`, always verify against the release's published `SHA256SUMS` (`grep '  app-release.apk$' SHA256SUMS | sha256sum -c -`) rather than hardcoding a prior release's APK digest.
3. **Tag, Push & Verify GitHub Release Assets:**
   - Commit `install.sh`, `README.md`, and `AGENT_INSTALL.md`, create annotated tag `vX.Y.Z`, and push `origin master vX.Y.Z`.
   - Watch `.github/workflows/build.yml` to completion and confirm that the GitHub Release for `vX.Y.Z` publishes `app-release.apk`, `install.sh` (with matching SHA-256), and `SHA256SUMS`.
