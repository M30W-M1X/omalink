import 'package:material_ui/material_ui.dart';

import '../services/bridge_client.dart';
import '../services/notification_service.dart';
import '../theme/wizard_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.client,
  });

  final BridgeClient client;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tokenController;
  late bool _demoMode;
  late bool _notifyOnComplete;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    final s = widget.client.settings;
    _hostController = TextEditingController(text: s.host);
    _portController = TextEditingController(text: s.port.toString());
    _tokenController = TextEditingController(text: s.token);
    _demoMode = s.demoMode;
    _notifyOnComplete = s.notifyOnComplete;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _saveAndConnect() async {
    final port = int.tryParse(_portController.text.trim()) ?? 7842;
    final next = widget.client.settings.copyWith(
      host: _hostController.text.trim(),
      port: port,
      token: _tokenController.text.trim(),
      demoMode: _demoMode,
      notifyOnComplete: _notifyOnComplete,
    );
    await widget.client.updateSettings(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _demoMode
              ? 'Demo Familiar Mode enabled ✨'
              : 'Connecting to Omarchy bridge at ${next.host}:${next.port}...',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.client.hostStatus;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text(
            'Sanctum Settings',
            style: TextStyle(
              color: WizardColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pair with your Omarchy AI agent bridge & configure alerts',
            style: TextStyle(color: WizardColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              title: const Text(
                'Demo Familiar Mode',
                style: TextStyle(
                  color: WizardColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Simulate agent spells & animations locally without a bridge connection.',
                style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
              ),
              activeThumbColor: WizardColors.cyanArcane,
              value: _demoMode,
              onChanged: (val) => setState(() => _demoMode = val),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'OMARCHY BRIDGE PAIRING',
                    style: TextStyle(
                      color: WizardColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hostController,
                    enabled: !_demoMode,
                    decoration: const InputDecoration(
                      labelText: 'Omarchy Host / Tailscale IP',
                      hintText: '192.168.1.100',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _portController,
                    enabled: !_demoMode,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bridge Port',
                      hintText: '7842',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    enabled: !_demoMode,
                    obscureText: _obscureToken,
                    decoration: InputDecoration(
                      labelText: 'Pairing Token (~/.config/omarchy-wizard/token)',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _saveAndConnect,
                    style: FilledButton.styleFrom(
                      backgroundColor: WizardColors.cyanArcane,
                      foregroundColor: WizardColors.obsidian,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(
                      _demoMode ? 'Save Settings' : 'Save & Connect Bridge',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'TASK COMPLETION NOTIFICATIONS',
                    style: TextStyle(
                      color: WizardColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Notify when tasks complete',
                      style: TextStyle(color: WizardColors.textPrimary),
                    ),
                    subtitle: const Text(
                      'Fires an Android alert when a spell finishes or fails.',
                      style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
                    ),
                    activeThumbColor: WizardColors.emeraldSage,
                    value: _notifyOnComplete,
                    onChanged: (val) => setState(() => _notifyOnComplete = val),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await NotificationService.instance
                                .requestPermission();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Notification permission granted ✨'
                                      : 'Enable notifications in Android system settings.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Grant Permission'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            await NotificationService.instance
                                .showTestNotification();
                          },
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Test Alert'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OMARCHY DEFAULT AGENT',
                    style: TextStyle(
                      color: WizardColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: status.availableAgents.map((agent) {
                      final isDefault = agent == status.defaultAgent;
                      return ChoiceChip(
                        label: Text(agent),
                        selected: isDefault,
                        selectedColor:
                            WizardColors.violetArcane.withValues(alpha: 0.28),
                        onSelected: (_) =>
                            widget.client.setDefaultOmarchyAgent(agent),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
