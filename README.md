# Omarchy Wizard 🧙‍♂️✨

A **Flutter Android app** + lightweight **Omarchy Bridge server** to remotely command your AI Agent (`agy`, `claude`, `codex`, `kimi`, `opencode`) running on **Omarchy Linux**, complete with **task-completion Android notifications** and **Arcane Agy** — a cute animated cosmic wizard mascot!

## Project Structure

- `android_app/` — Flutter Android app
  - **Arcane Agy Mascot** (`lib/widgets/arcane_wizard_mascot.dart`): Hand-crafted animated `CustomPainter` wizard with a slouchy rune-banded hat, dangling golden star charm, floating spellbook, glowing crystal staff, orbiting arcane rune ring, blinking expressive eyes, and state-driven animations (`idle`, `listening`, `casting`, `awaitingApproval`, `celebrating`, `error`). Tap the wizard to boop it!
  - **Notifications** (`lib/services/notification_service.dart`): Uses `flutter_local_notifications` with a high-importance Android notification channel (`omarchy_wizard_tasks`) to alert you whenever a task finishes or fails.
  - **Demo Familiar Mode**: Built-in simulation mode so you can preview animations, spell logs, and test notifications before pairing with your Omarchy machine.
- `bridge/` — Pure Python 3 standard-library HTTP + WebSocket bridge (`omarchy_wizard_bridge.py`)
  - Launches and streams `agy -p --output-format stream-json`, `claude`, `codex`, `kimi`, or `opencode`.
  - Reads/updates Omarchy's default agent (`omarchy-default-agent` / `~/.config/omarchy/defaults/agent`).
  - Broadcasts live `task.started`, `task.event`, `task.completed`, `task.failed`, and `task.cancelled` WebSocket events.

---

## 1. Start the Omarchy Bridge

No pip dependencies needed (Python 3.11+ standard library only):

```bash
python3 ~/Projects/omarchy_wizard/bridge/omarchy_wizard_bridge.py
```

On first run, it generates a secure pairing token at `~/.config/omarchy-wizard/token` and prints your LAN IP, port (`7842`), and token.

### Optional: Run as a systemd user service

```bash
mkdir -p ~/.config/systemd/user
cp ~/Projects/omarchy_wizard/bridge/omarchy-wizard-bridge.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now omarchy-wizard-bridge.service
```

Run bridge tests:

```bash
PYTHONPATH=~/Projects/omarchy_wizard/bridge python3 -m unittest discover -s ~/Projects/omarchy_wizard/bridge -v
```

---

## 2. Build & Run the Flutter Android App

```bash
cd ~/Projects/omarchy_wizard/android_app
flutter pub get
flutter test
flutter build apk --release
# Or install directly onto a connected Android phone:
flutter run
```

### Pairing the App

1. Open **Omarchy Wizard** on your Android phone.
2. Go to the **Sanctum** (Settings) tab.
3. Toggle **Demo Familiar Mode** off.
4. Enter your Omarchy machine's LAN or Tailscale IP, port `7842`, and the token from `~/.config/omarchy-wizard/token`.
5. Tap **Grant Permission** under Task Completion Notifications and **Test Alert** to verify Android notifications!
