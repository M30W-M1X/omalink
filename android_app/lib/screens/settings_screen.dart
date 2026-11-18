import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/bridge_client.dart';
import '../services/continuity_service.dart';
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
  late final TextEditingController _fpController;
  late bool _demoMode;
  late bool _notifyOnComplete;
  late bool _useTls;
  bool _obscureToken = true;
  bool _discovering = false;
  List<DiscoveredBridge> _discovered = const [];

  @override
  void initState() {
    super.initState();
    final s = widget.client.settings;
    _hostController = TextEditingController(text: s.host);
    _portController = TextEditingController(text: s.port.toString());
    _tokenController = TextEditingController(text: s.token);
    _fpController = TextEditingController(text: s.tlsFingerprint);
    _demoMode = s.demoMode;
    _notifyOnComplete = s.notifyOnComplete;
    _useTls = s.useTls;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _fpController.dispose();
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
      useTls: _useTls,
      tlsFingerprint: _fpController.text.trim(),
    );
    await widget.client.updateSettings(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _demoMode
              ? 'Demo Familiar Mode enabled ✨'
              : 'Connecting to Omarchy bridge at ${next.httpBaseUrl}...',
        ),
      ),
    );
  }

  Future<void> _discoverLan() async {
    setState(() => _discovering = true);
    final found = await widget.client.discoverLanBridges();
    if (!mounted) return;
    setState(() {
      _discovering = false;
      _discovered = found;
    });
    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No LAN bridges found via mDNS — check Wi-Fi or scan QR.')),
      );
    }
  }

  Future<void> _pastePairUri() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clip?.text?.trim() ?? '';
    final ok = await widget.client.applyPairingUri(raw);
    if (!mounted) return;
    if (ok) {
      final s = widget.client.settings;
      setState(() {
        _hostController.text = s.host;
        _portController.text = s.port.toString();
        _tokenController.text = s.token;
        _fpController.text = s.tlsFingerprint;
        _useTls = s.useTls;
        _demoMode = false;
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Paired via omarchy-wizard:// URI ✨'
              : 'Copy an omarchy-wizard://pair?... URI or scan the Omarchy top bar QR.',
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
          Text(
            'Sanctum Settings',
            style: TextStyle(
              color: WizardColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pair with your Omarchy AI agent bridge & configure alerts',
            style: TextStyle(color: WizardColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              title: Text(
                'Demo Familiar Mode',
                style: TextStyle(
                  color: WizardColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
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
                  Text(
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _discovering ? null : _discoverLan,
                          icon: _discovering
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.radar_rounded, size: 17),
                          label: const Text('Scan LAN (mDNS)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pastePairUri,
                          icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                          label: const Text('Paste Pair URI'),
                        ),
                      ),
                    ],
                  ),
                  if (_discovered.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _discovered.map((b) {
                        return ActionChip(
                          avatar: Icon(Icons.computer_rounded, size: 16, color: WizardColors.cyanArcane),
                          label: Text('${b.name} (${b.host}:${b.port})'),
                          onPressed: () {
                            setState(() {
                              _demoMode = false;
                              _hostController.text = b.host;
                              _portController.text = b.port.toString();
                              _useTls = b.tls;
                              _fpController.text = b.fingerprint;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  if (widget.client.detectedTailscaleIp.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: Icon(Icons.vpn_lock_rounded, size: 16, color: WizardColors.emeraldSage),
                        label: Text('Use Tailscale IP (${widget.client.detectedTailscaleIp})'),
                        onPressed: () {
                          setState(() {
                            _demoMode = false;
                            _hostController.text = widget.client.detectedTailscaleIp;
                          });
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Tip: Open the Wizard icon in your Omarchy top bar → QR, and scan with your phone camera for 1-tap pairing.',
                    style: TextStyle(color: WizardColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'TLS Encryption (HTTPS / WSS)',
                      style: TextStyle(color: WizardColors.textPrimary, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Enable if bridge runs with --tls (optional SHA-256 cert pin).',
                      style: TextStyle(color: WizardColors.textMuted, fontSize: 11),
                    ),
                    value: _useTls,
                    onChanged: _demoMode ? null : (v) => setState(() => _useTls = v),
                  ),
                  if (_useTls) ...[
                    TextField(
                      controller: _fpController,
                      enabled: !_demoMode,
                      decoration: const InputDecoration(
                        labelText: 'Pinned TLS SHA-256 Fingerprint (optional)',
                        hintText: 'Auto-filled from QR code',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
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
                  Text(
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
                    title: Text(
                      'Notify when tasks complete',
                      style: TextStyle(color: WizardColors.textPrimary),
                    ),
                    subtitle: Text(
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
                            final err = await NotificationService.instance
                                .showTestNotification();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  err ?? 'Test alert sent ✨',
                                ),
                                backgroundColor:
                                    err != null ? WizardColors.coralError : null,
                              ),
                            );
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'APPEARANCE & OMARCHY THEME',
                          style: TextStyle(
                            color: WizardColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final dot in [
                            widget.client.activePalette.obsidian,
                            widget.client.activePalette.violetArcane,
                            widget.client.activePalette.cyanArcane,
                            widget.client.activePalette.emeraldSage,
                          ])
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: dot,
                                shape: BoxShape.circle,
                                border: Border.all(color: WizardColors.borderSubtle),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Match Omarchy Desktop Theme',
                      style: TextStyle(color: WizardColors.textPrimary),
                    ),
                    subtitle: Text(
                      widget.client.settings.syncOmarchyTheme
                          ? 'Live synced: ${widget.client.activePalette.name} (${widget.client.activePalette.isLight ? 'light' : 'dark'})'
                          : 'Manual override: ${widget.client.activePalette.name}',
                      style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
                    ),
                    activeThumbColor: WizardColors.cyanArcane,
                    value: widget.client.settings.syncOmarchyTheme,
                    onChanged: (val) => widget.client.updateThemePreferences(
                      syncOmarchyTheme: val,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in WizardPalette.presets)
                        ChoiceChip(
                          label: Text(preset.name),
                          selected: widget.client.activePalette.slug == preset.slug,
                          selectedColor:
                              WizardColors.violetArcane.withValues(alpha: 0.28),
                          onSelected: (_) {
                            if (widget.client.settings.demoMode &&
                                widget.client.settings.syncOmarchyTheme) {
                              widget.client.sendControlAction(
                                'theme.set',
                                params: {'name': preset.name},
                              );
                            } else {
                              widget.client.updateThemePreferences(
                                syncOmarchyTheme: false,
                                themeOverride: preset.slug,
                              );
                            }
                          },
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
                  Text(
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
