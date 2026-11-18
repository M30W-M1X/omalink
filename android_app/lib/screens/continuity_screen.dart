import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';

class ContinuityScreen extends StatefulWidget {
  const ContinuityScreen({
    super.key,
    required this.client,
  });

  final BridgeClient client;

  @override
  State<ContinuityScreen> createState() => _ContinuityScreenState();
}

class _ContinuityScreenState extends State<ContinuityScreen>
    with WidgetsBindingObserver {
  final TextEditingController _handoffController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.client.refreshContinuityState());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.client.refreshNotificationAccessStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _handoffController.dispose();
    super.dispose();
  }

  IconData _appIcon(String id) {
    switch (id) {
      case 'browser':
        return Icons.public_rounded;
      case 'spotify':
        return Icons.music_note_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'files':
        return Icons.folder_open_rounded;
      case 'editor':
        return Icons.edit_note_rounded;
      case 'signal':
        return Icons.chat_bubble_outline_rounded;
      case '1password':
        return Icons.vpn_key_outlined;
      default:
        return Icons.launch_rounded;
    }
  }

  IconData _activityIcon(String category) {
    switch (category) {
      case 'call':
        return Icons.call_rounded;
      case 'message':
        return Icons.sms_outlined;
      case 'clipboard':
        return Icons.content_paste_rounded;
      case 'handoff':
        return Icons.open_in_browser_rounded;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.client,
      builder: (context, _) {
        final client = widget.client;
        final settings = client.settings;
        final banner = client.continuityBanner;

        return Scaffold(
          backgroundColor: WizardColors.obsidian,
          appBar: AppBar(
            backgroundColor: WizardColors.obsidian,
            title: Text(
              'Omarchy Continuity',
              style: TextStyle(
                color: WizardColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh Continuity',
                onPressed: client.refreshContinuityState,
                icon: Icon(Icons.refresh_rounded, color: WizardColors.cyanArcane),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              if (banner != null && banner.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: WizardColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WizardColors.cyanArcane.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: WizardColors.cyanArcane),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          banner,
                          style: TextStyle(color: WizardColors.textPrimary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Phone notifications & call relay
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'PHONE → DESKTOP ALERTS',
                              style: TextStyle(
                                color: WizardColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: client.notificationAccessEnabled
                                  ? WizardColors.emeraldSage.withValues(alpha: 0.16)
                                  : WizardColors.goldStarlight.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              client.notificationAccessEnabled ? 'ACTIVE' : 'ACCESS NEEDED',
                              style: TextStyle(
                                color: client.notificationAccessEnabled
                                    ? WizardColors.emeraldSage
                                    : WizardColors.goldStarlight,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Mirror incoming phone messages and calls onto your Hyprland desktop in real time.',
                        style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Relay Messages & App Notifications',
                          style: TextStyle(color: WizardColors.textPrimary, fontSize: 14),
                        ),
                        value: settings.relayNotifications,
                        onChanged: (v) => unawaited(
                          client.updateRelayPreferences(relayNotifications: v),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Critical Popups for Incoming Calls',
                          style: TextStyle(color: WizardColors.textPrimary, fontSize: 14),
                        ),
                        value: settings.relayCalls,
                        onChanged: (v) => unawaited(
                          client.updateRelayPreferences(relayCalls: v),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (!client.notificationAccessEnabled)
                            FilledButton.icon(
                              onPressed: client.openNotificationAccessSettings,
                              style: FilledButton.styleFrom(
                                backgroundColor: WizardColors.goldStarlight,
                                foregroundColor: WizardColors.obsidian,
                              ),
                              icon: const Icon(Icons.notifications_active_outlined, size: 17),
                              label: const Text('Enable Notification Access'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => unawaited(
                              client.relayNotificationToOmarchy(
                                title: 'Test Message from Phone',
                                body: 'Messages & SMS mirror is working!',
                                appName: 'Messages',
                                category: 'message',
                              ),
                            ),
                            icon: const Icon(Icons.sms_outlined, size: 16),
                            label: const Text('Test Message'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => unawaited(
                              client.relayNotificationToOmarchy(
                                title: 'Alex',
                                caller: 'Alex',
                                body: 'Incoming mobile call',
                                appName: 'Phone',
                                category: 'call',
                              ),
                            ),
                            icon: Icon(Icons.call_rounded, size: 16, color: WizardColors.emeraldSage),
                            label: const Text('Test Call'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Universal Clipboard
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UNIVERSAL CLIPBOARD',
                        style: TextStyle(
                          color: WizardColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => unawaited(client.sendClipboardToOmarchy()),
                              style: FilledButton.styleFrom(
                                backgroundColor: WizardColors.cyanArcane,
                                foregroundColor: WizardColors.obsidian,
                              ),
                              icon: const Icon(Icons.upload_rounded, size: 18),
                              label: const Text('Send to PC'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => unawaited(client.pullClipboardFromOmarchy()),
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('Pull from PC'),
                            ),
                          ),
                        ],
                      ),
                      if (client.desktopClipboardPreview.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: WizardColors.obsidian,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: WizardColors.borderSubtle),
                          ),
                          child: Text(
                            client.desktopClipboardPreview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: WizardColors.textMuted,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Continue on Omarchy (Handoff)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTINUE ON OMARCHY',
                        style: TextStyle(
                          color: WizardColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tip: In Chrome, YouTube, or Spotify on Android, tap Share → Continue on Omarchy.',
                        style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _handoffController,
                              style: TextStyle(color: WizardColors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Paste Chrome URL, Spotify link, or text...',
                                hintStyle: TextStyle(color: WizardColors.textMuted),
                                isDense: true,
                                filled: true,
                                fillColor: WizardColors.obsidian,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) {
                                final value = _handoffController.text.trim();
                                if (value.isNotEmpty) {
                                  unawaited(client.handoffToOmarchy(text: value));
                                  _handoffController.clear();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              final value = _handoffController.text.trim();
                              if (value.isNotEmpty) {
                                unawaited(client.handoffToOmarchy(text: value));
                                _handoffController.clear();
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: WizardColors.violetArcane,
                              foregroundColor: WizardColors.obsidian,
                            ),
                            child: const Text('Open'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final app in client.continuityApps)
                            if (app['available'] != false)
                              ActionChip(
                                avatar: Icon(
                                  _appIcon(app['id']?.toString() ?? ''),
                                  size: 16,
                                  color: WizardColors.cyanArcane,
                                ),
                                label: Text(app['label']?.toString() ?? ''),
                                onPressed: () => unawaited(
                                  client.handoffToOmarchy(app: app['id']?.toString() ?? ''),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Activity Log
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RECENT CONTINUITY ACTIVITY',
                        style: TextStyle(
                          color: WizardColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (client.continuityActivity.isEmpty)
                        Text(
                          'No relayed notifications, clipboard syncs, or handoffs yet.',
                          style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
                        )
                      else
                        for (final item in client.continuityActivity.take(10))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _activityIcon(item['category']?.toString() ?? ''),
                                  size: 16,
                                  color: WizardColors.violetArcane,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['title']?.toString() ?? '',
                                        style: TextStyle(
                                          color: WizardColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if ((item['body']?.toString() ?? '').isNotEmpty)
                                        Text(
                                          item['body']?.toString() ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: WizardColors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
