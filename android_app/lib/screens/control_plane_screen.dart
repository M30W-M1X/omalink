import 'package:material_ui/material_ui.dart';

import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';
import 'continuity_screen.dart';
import 'desktop_screen.dart';

class ControlPlaneScreen extends StatefulWidget {
  const ControlPlaneScreen({
    super.key,
    required this.client,
  });

  final BridgeClient client;

  @override
  State<ControlPlaneScreen> createState() => _ControlPlaneScreenState();
}

class _ControlPlaneScreenState extends State<ControlPlaneScreen> {
  double? _pendingVolume;

  Future<void> _dispatch(String action, {Map<String, dynamic>? params}) async {
    final ok = await widget.client.sendControlAction(action, params: params);
    if (!mounted) return;
    final msg = widget.client.systemMessage;
    if (msg != null && msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: ok ? null : WizardColors.coralError,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmPowerAction({
    required String title,
    required String body,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WizardColors.surfaceCard,
        title: Text(
          title,
          style: TextStyle(color: WizardColors.textPrimary),
        ),
        content: Text(
          body,
          style: TextStyle(color: WizardColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WizardColors.coralError,
              foregroundColor: WizardColors.obsidian,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _dispatch(action);
    }
  }

  String _formatUptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final s = client.systemState;
    final volValue = _pendingVolume ?? s.audio.volume.toDouble().clamp(0, 100);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: client.refreshSystemState,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Omarchy Control Plane',
                        style: TextStyle(
                          color: WizardColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.hostname} • Omarchy ${s.osVersion} • up ${_formatUptime(s.uptimeSeconds)}',
                        style: TextStyle(
                          color: WizardColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Continuity & Phone Relay',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ContinuityScreen(client: client),
                      ),
                    );
                  },
                  icon: Icon(Icons.devices_rounded, color: WizardColors.emeraldSage),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DesktopScreen(client: client),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: WizardColors.surfaceElevated,
                    foregroundColor: WizardColors.cyanArcane,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.desktop_windows_outlined, size: 16),
                  label: const Text('Desktop', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Refresh OS State',
                  onPressed: client.systemLoading ? null : client.refreshSystemState,
                  icon: client.systemLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.refresh_rounded, color: WizardColors.cyanArcane),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Telemetry bar
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('MACHINE VITALS'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _VitalTile(
                          label: 'CPU',
                          value: '${s.cpuPercent.toStringAsFixed(0)}%',
                          sub: 'load ${s.loadAvg}',
                          color: WizardColors.cyanArcane,
                        ),
                        const SizedBox(width: 8),
                        _VitalTile(
                          label: 'RAM',
                          value: '${s.memory.usedGb} / ${s.memory.totalGb} GB',
                          sub: '${s.memory.percent.toStringAsFixed(0)}% used',
                          color: WizardColors.violetArcane,
                        ),
                        if (s.battery.present) ...[
                          const SizedBox(width: 8),
                          _VitalTile(
                            label: 'BATTERY',
                            value: '${s.battery.percent}%',
                            sub: s.battery.status,
                            color: WizardColors.emeraldSage,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Audio & Media Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: _SectionTitle('AUDIO & MEDIA')),
                        Text(
                          s.audio.muted ? 'MUTED (${volValue.round()}%)' : '${volValue.round()}%',
                          style: TextStyle(
                            color: s.audio.muted
                                ? WizardColors.coralError
                                : WizardColors.cyanArcane,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: volValue,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '${volValue.round()}%',
                      onChanged: (v) => setState(() => _pendingVolume = v),
                      onChangeEnd: (v) async {
                        setState(() => _pendingVolume = null);
                        await _dispatch(
                          'audio.set_volume',
                          params: {'percent': v.round()},
                        );
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ActionChipButton(
                          icon: s.audio.muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          label: s.audio.muted ? 'Unmute' : 'Mute',
                          active: s.audio.muted,
                          activeColor: WizardColors.coralError,
                          onTap: () => _dispatch('audio.toggle_mute'),
                        ),
                        _ActionChipButton(
                          icon: s.audio.micMuted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: s.audio.micMuted ? 'Mic Muted' : 'Mic Live',
                          active: s.audio.micMuted,
                          activeColor: WizardColors.goldStarlight,
                          onTap: () => _dispatch('audio.toggle_mic_mute'),
                        ),
                        _ActionChipButton(
                          icon: Icons.skip_previous_rounded,
                          label: 'Prev',
                          onTap: () => _dispatch(
                            'media.previous',
                            params: {
                              if (s.audio.player.busName.isNotEmpty)
                                'bus_name': s.audio.player.busName,
                            },
                          ),
                        ),
                        _ActionChipButton(
                          icon: s.audio.player.status == 'Playing'
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          label: s.audio.player.status == 'Playing' ? 'Pause' : 'Play',
                          active: s.audio.player.status == 'Playing',
                          onTap: () => _dispatch(
                            'media.play_pause',
                            params: {
                              if (s.audio.player.busName.isNotEmpty)
                                'bus_name': s.audio.player.busName,
                            },
                          ),
                        ),
                        _ActionChipButton(
                          icon: Icons.skip_next_rounded,
                          label: 'Next',
                          onTap: () => _dispatch(
                            'media.next',
                            params: {
                              if (s.audio.player.busName.isNotEmpty)
                                'bus_name': s.audio.player.busName,
                            },
                          ),
                        ),
                        if (s.audio.player.shuffle != null)
                          _ActionChipButton(
                            icon: Icons.shuffle_rounded,
                            label: 'Shuffle',
                            active: s.audio.player.shuffle == true,
                            onTap: () => _dispatch(
                              'media.toggle_shuffle',
                              params: {
                                if (s.audio.player.busName.isNotEmpty)
                                  'bus_name': s.audio.player.busName,
                              },
                            ),
                          ),
                        if (s.audio.player.loopStatus != null)
                          _ActionChipButton(
                            icon: s.audio.player.loopStatus == 'Track'
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            label: 'Loop: ${s.audio.player.loopStatus}',
                            active: s.audio.player.loopStatus != 'None',
                            onTap: () => _dispatch(
                              'media.cycle_loop',
                              params: {
                                if (s.audio.player.busName.isNotEmpty)
                                  'bus_name': s.audio.player.busName,
                              },
                            ),
                          ),
                      ],
                    ),
                    if (s.audio.player.available) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: WizardColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: WizardColors.borderSubtle),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: s.audio.player.artUrl.startsWith('http')
                                  ? Image.network(
                                      s.audio.player.artUrl,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const _FallbackArt(),
                                    )
                                  : const _FallbackArt(),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.audio.player.title.isNotEmpty
                                        ? s.audio.player.title
                                        : s.audio.player.identity,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: WizardColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (s.audio.player.artist.isNotEmpty ||
                                      s.audio.player.album.isNotEmpty)
                                    Text(
                                      [
                                        if (s.audio.player.artist.isNotEmpty) s.audio.player.artist,
                                        if (s.audio.player.album.isNotEmpty) s.audio.player.album,
                                      ].join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: WizardColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              s.audio.player.identity.toUpperCase(),
                              style: TextStyle(
                                color: WizardColors.emeraldSage,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (s.audio.players.length > 1) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Media Player',
                        style: TextStyle(color: WizardColors.textMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: s.audio.players.map((p) {
                          return ChoiceChip(
                            label: Text('${p.identity} (${p.status})'),
                            selected: p.busName == s.audio.player.busName,
                            onSelected: (_) => _dispatch(
                              'media.select_player',
                              params: {'bus_name': p.busName},
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (s.audio.sinks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Output Device',
                        style: TextStyle(color: WizardColors.textMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: s.audio.sinks.map((sink) {
                          return ChoiceChip(
                            label: Text(
                              sink.displayLabel,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: sink.active,
                            onSelected: (_) => _dispatch(
                              'audio.set_sink',
                              params: {'id': sink.id, 'name': sink.name},
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Display & Omarchy Toggles
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('OMARCHY TOGGLES & DISPLAY'),
                    if (s.brightness.available) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.brightness_6_rounded, size: 18, color: WizardColors.goldStarlight),
                          const SizedBox(width: 8),
                          Text(
                            'Brightness: ${s.brightness.percent}%',
                            style: TextStyle(color: WizardColors.textPrimary, fontSize: 13),
                          ),
                          const Spacer(),
                          OutlinedButton(
                            onPressed: () => _dispatch('brightness.step', params: {'delta': '10%-'}),
                            child: const Text('-10%'),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton(
                            onPressed: () => _dispatch('brightness.step', params: {'delta': '+10%'}),
                            child: const Text('+10%'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ActionChipButton(
                          icon: Icons.nightlight_round,
                          label: 'Nightlight',
                          active: s.toggles.nightlight,
                          activeColor: WizardColors.goldStarlight,
                          onTap: () => _dispatch('toggle.nightlight'),
                        ),
                        _ActionChipButton(
                          icon: Icons.coffee_rounded,
                          label: 'Stay Awake',
                          active: s.toggles.stayAwake,
                          activeColor: WizardColors.emeraldSage,
                          onTap: () => _dispatch('toggle.idle'),
                        ),
                        _ActionChipButton(
                          icon: Icons.web_asset_off_rounded,
                          label: s.toggles.barHidden ? 'Bar Hidden' : 'Top Bar On',
                          active: s.toggles.barHidden,
                          onTap: () => _dispatch('toggle.bar'),
                        ),
                        _ActionChipButton(
                          icon: Icons.animation_rounded,
                          label: s.toggles.animationsOff ? 'Animations Off' : 'Animations On',
                          active: s.toggles.animationsOff,
                          onTap: () => _dispatch('toggle.animations'),
                        ),
                        _ActionChipButton(
                          icon: Icons.screen_lock_landscape_rounded,
                          label: s.toggles.screensaverOff ? 'Saver Off' : 'Saver On',
                          active: s.toggles.screensaverOff,
                          onTap: () => _dispatch('toggle.screensaver'),
                        ),
                        _ActionChipButton(
                          icon: Icons.notifications_off_outlined,
                          label: 'Toggle DND',
                          onTap: () => _dispatch('toggle.dnd'),
                        ),
                        if (s.security.bluetoothPowered != null)
                          _ActionChipButton(
                            icon: Icons.bluetooth_rounded,
                            label: s.security.bluetoothPowered == true
                                ? 'Bluetooth On'
                                : 'Bluetooth Off',
                            active: s.security.bluetoothPowered == true,
                            onTap: () => _dispatch('toggle.bluetooth'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Hyprland & Desktop Launchers
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('DESKTOP & HYPRLAND'),
                    if (s.hyprland.activeWindow.title.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: WizardColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.window_rounded, size: 16, color: WizardColors.cyanArcane),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.hyprland.activeWindow.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: WizardColors.textPrimary, fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _dispatch('hyprland.close_active'),
                              child: Text(
                                'Close',
                                style: TextStyle(color: WizardColors.coralError, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (s.hyprland.workspaces.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: s.hyprland.workspaces.map((ws) {
                          return ChoiceChip(
                            label: Text('WS ${ws.name} (${ws.windows})'),
                            selected: ws.active,
                            onSelected: (_) => _dispatch(
                              'hyprland.workspace',
                              params: {'id': ws.id},
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ActionChipButton(
                          icon: Icons.folder_open_rounded,
                          label: 'Open Files',
                          onTap: () => _dispatch('hyprland.launch_files'),
                        ),
                        _ActionChipButton(
                          icon: Icons.terminal_rounded,
                          label: 'Terminal',
                          onTap: () => _dispatch('hyprland.launch_terminal'),
                        ),
                        _ActionChipButton(
                          icon: Icons.public_rounded,
                          label: 'Browser',
                          onTap: () => _dispatch('hyprland.launch_browser'),
                        ),
                        _ActionChipButton(
                          icon: Icons.wallpaper_rounded,
                          label: 'Next Wallpaper',
                          onTap: () => _dispatch('theme.next_bg'),
                        ),
                        _ActionChipButton(
                          icon: Icons.screenshot_monitor_rounded,
                          label: 'Screenshot',
                          onTap: () => _dispatch('system.screenshot'),
                        ),
                        _ActionChipButton(
                          icon: Icons.auto_awesome_rounded,
                          label: 'Screensaver',
                          onTap: () => _dispatch('system.screensaver'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Security & Passwordless Sudo Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: _SectionTitle('SECURITY & PASSWORDLESS SUDO')),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (s.security.passwordlessSudo
                                    ? WizardColors.goldStarlight
                                    : WizardColors.emeraldSage)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            s.security.passwordlessSudo ? 'ACTIVE' : 'PROTECTED',
                            style: TextStyle(
                              color: s.security.passwordlessSudo
                                  ? WizardColors.goldStarlight
                                  : WizardColors.emeraldSage,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.security.passwordlessSudo
                          ? 'omarchy-sudo-passwordless is currently active on ${s.hostname}. You can revoke it immediately from your phone.'
                          : 'Enabling passwordless sudo opens Omarchy\'s local desktop confirmation & sudo prompt for safety.',
                      style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (s.security.passwordlessSudo)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: WizardColors.coralError,
                              foregroundColor: WizardColors.obsidian,
                            ),
                            onPressed: () => _dispatch('security.sudo_disable'),
                            icon: const Icon(Icons.lock_rounded, size: 18),
                            label: const Text('Disable Passwordless Sudo'),
                          ),
                        _ActionChipButton(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Prompt 15m',
                          onTap: () => _dispatch('security.sudo_prompt', params: {'duration': '15'}),
                        ),
                        _ActionChipButton(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Prompt 1h',
                          onTap: () => _dispatch('security.sudo_prompt', params: {'duration': '60'}),
                        ),
                        _ActionChipButton(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Prompt 1d',
                          onTap: () => _dispatch('security.sudo_prompt', params: {'duration': '1440'}),
                        ),
                        _ActionChipButton(
                          icon: Icons.verified_user_outlined,
                          label: 'Prompt Permanent',
                          onTap: () => _dispatch('security.sudo_prompt', params: {'duration': 'permanent'}),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Omarchy Themes Card
            if (s.theme.themes.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle('OMARCHY THEME (${s.theme.current})'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: s.theme.themes.map((themeName) {
                          return ChoiceChip(
                            label: Text(themeName),
                            selected: themeName == s.theme.current,
                            onSelected: (_) => _dispatch(
                              'theme.set',
                              params: {'name': themeName},
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Power & Services Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('POWER & SERVICES'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ActionChipButton(
                          icon: Icons.lock_outline_rounded,
                          label: 'Lock Screen',
                          onTap: () => _dispatch('system.lock'),
                        ),
                        _ActionChipButton(
                          icon: Icons.audiotrack_rounded,
                          label: 'Restart Audio',
                          onTap: () => _dispatch('system.restart_audio'),
                        ),
                        _ActionChipButton(
                          icon: Icons.wifi_rounded,
                          label: 'Restart Wi-Fi',
                          onTap: () => _dispatch('system.restart_wifi'),
                        ),
                        _ActionChipButton(
                          icon: Icons.refresh_rounded,
                          label: 'Restart Shell',
                          onTap: () => _dispatch('system.restart_shell'),
                        ),
                        _ActionChipButton(
                          icon: Icons.logout_rounded,
                          label: 'Logout',
                          active: true,
                          activeColor: WizardColors.goldStarlight,
                          onTap: () => _confirmPowerAction(
                            title: 'Logout Session?',
                            body: 'Closes active windows and logs out of Omarchy.',
                            action: 'system.logout',
                          ),
                        ),
                        _ActionChipButton(
                          icon: Icons.restart_alt_rounded,
                          label: 'Reboot',
                          active: true,
                          activeColor: WizardColors.coralError,
                          onTap: () => _confirmPowerAction(
                            title: 'Reboot Computer?',
                            body: 'Gracefully closes apps and reboots ${s.hostname}.',
                            action: 'system.reboot',
                          ),
                        ),
                        _ActionChipButton(
                          icon: Icons.power_settings_new_rounded,
                          label: 'Shutdown',
                          active: true,
                          activeColor: WizardColors.coralError,
                          onTap: () => _confirmPowerAction(
                            title: 'Shut Down Computer?',
                            body: 'Powers off ${s.hostname}. Your bridge will disconnect.',
                            action: 'system.shutdown',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: WizardColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _VitalTile extends StatelessWidget {
  const _VitalTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  final String label;
  final String value;
  final String sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: WizardColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: WizardColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(color: WizardColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final accent = activeColor ?? WizardColors.cyanArcane;
    return ActionChip(
      avatar: Icon(
        icon,
        size: 16,
        color: active ? accent : WizardColors.textMuted,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: active ? accent : WizardColors.textPrimary,
          fontSize: 12,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      side: BorderSide(
        color: active ? accent.withValues(alpha: 0.6) : WizardColors.borderSubtle,
      ),
      backgroundColor: active
          ? accent.withValues(alpha: 0.14)
          : WizardColors.surfaceElevated,
      onPressed: onTap,
    );
  }
}

class _FallbackArt extends StatelessWidget {
  const _FallbackArt();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      color: WizardColors.obsidian,
      child: Icon(
        Icons.music_note_rounded,
        color: WizardColors.cyanArcane,
        size: 22,
      ),
    );
  }
}
