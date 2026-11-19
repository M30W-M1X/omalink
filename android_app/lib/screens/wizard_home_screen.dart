import 'package:material_ui/material_ui.dart';

import '../models/agent_task.dart';
import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';
import '../widgets/arcane_wizard_mascot.dart';
import '../widgets/quick_cast_bar.dart';
import '../widgets/spell_log_view.dart';
import '../widgets/status_pill.dart';
import 'continuity_screen.dart';
import 'desktop_screen.dart';
import 'spellbook_screen.dart';
import 'trackpad_screen.dart';

class WizardHomeScreen extends StatefulWidget {
  const WizardHomeScreen({
    super.key,
    required this.client,
    required this.onOpenSettings,
  });

  final BridgeClient client;
  final VoidCallback onOpenSettings;

  @override
  State<WizardHomeScreen> createState() => _WizardHomeScreenState();
}

class _WizardHomeScreenState extends State<WizardHomeScreen> {
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocus = FocusNode();
  String? _replyConversationId;

  @override
  void initState() {
    super.initState();
    _promptFocus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    widget.client.setListeningMood(_promptFocus.hasFocus);
  }

  @override
  void dispose() {
    _promptFocus.removeListener(_onFocusChanged);
    _promptFocus.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _cast() async {
    final text = _promptController.text.trim();
    if (text.isEmpty) return;
    _promptFocus.unfocus();
    final convId = _replyConversationId;
    _replyConversationId = null;
    _promptController.clear();
    await widget.client.castSpell(text, conversationId: convId);
  }

  void _openDesktop() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DesktopScreen(
          client: widget.client,
          onOpenSettings: widget.onOpenSettings,
        ),
      ),
    );
  }

  void _openTrackpad() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackpadScreen(client: widget.client),
      ),
    );
  }

  void _openContinuity() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContinuityScreen(client: widget.client),
      ),
    );
  }

  void _openSpellbook() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Spellbook'),
            backgroundColor: WizardColors.obsidian,
          ),
          body: SpellbookScreen(
            client: widget.client,
            onInspectInHome: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }

  void _openToolsMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WizardColors.surfaceCard,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COMPANION TOOLS',
                  style: TextStyle(
                    color: WizardColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                _ToolMenuTile(
                  icon: Icons.desktop_windows_outlined,
                  accent: WizardColors.cyanArcane,
                  title: 'Remote Desktop',
                  subtitle: 'View your Omarchy screen, zoom, click & type',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openDesktop();
                  },
                ),
                _ToolMenuTile(
                  icon: Icons.touch_app_rounded,
                  accent: WizardColors.violetArcane,
                  title: 'Wireless Trackpad & Slides',
                  subtitle: 'Low-latency mouse touchpad & presentation remote',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openTrackpad();
                  },
                ),
                _ToolMenuTile(
                  icon: Icons.devices_rounded,
                  accent: WizardColors.emeraldSage,
                  title: 'Continuity & Notifications',
                  subtitle: 'Mirror calls/messages, sync clipboard & open links',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openContinuity();
                  },
                ),
                _ToolMenuTile(
                  icon: Icons.history_rounded,
                  accent: WizardColors.goldStarlight,
                  title: 'Spellbook History',
                  subtitle: 'Browse past AI agent tasks, diffs & outputs',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openSpellbook();
                  },
                ),
                _ToolMenuTile(
                  icon: Icons.tune_rounded,
                  accent: WizardColors.textMuted,
                  title: 'Pairing, Theme & Alerts',
                  subtitle: 'QR / mDNS pairing, TLS, Omarchy theme & vitals shade',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.onOpenSettings();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final activeTask = client.activeOrSelectedTask;
    final draft = client.consumePendingPromptDraft();
    if (draft != null && _promptController.text.isEmpty) {
      _promptController.text = draft;
    }

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: StatusPill(
                        state: client.connectionState,
                        hostname: client.hostStatus.hostname,
                        osVersion: client.hostStatus.osVersion,
                        onTap: widget.onOpenSettings,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _openToolsMenu,
                      style: FilledButton.styleFrom(
                        backgroundColor: WizardColors.surfaceElevated,
                        foregroundColor: WizardColors.textPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      icon: const Icon(Icons.menu_rounded, size: 18),
                      label: const Text(
                        'Tools',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: ArcaneWizardMascot(
                    mood: client.mood,
                    quip: client.wizardQuip,
                    onTap: client.triggerWizardBoop,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickToolTile(
                        icon: Icons.desktop_windows_outlined,
                        label: 'Desktop',
                        accent: WizardColors.cyanArcane,
                        onTap: _openDesktop,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickToolTile(
                        icon: Icons.touch_app_rounded,
                        label: 'Trackpad',
                        accent: WizardColors.violetArcane,
                        onTap: _openTrackpad,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickToolTile(
                        icon: Icons.devices_rounded,
                        label: 'Continuity',
                        accent: WizardColors.emeraldSage,
                        onTap: _openContinuity,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuickToolTile(
                        icon: Icons.history_rounded,
                        label: 'History',
                        accent: WizardColors.goldStarlight,
                        onTap: _openSpellbook,
                      ),
                    ),
                  ],
                ),
                if (client.isRinging) ...[
                  const SizedBox(height: 10),
                  Card(
                    color: WizardColors.coralError.withValues(alpha: 0.2),
                    child: ListTile(
                      leading: Icon(Icons.notifications_active, color: WizardColors.coralError),
                      title: Text(
                        'Omarchy is ringing your phone!',
                        style: TextStyle(color: WizardColors.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      trailing: FilledButton(
                        onPressed: client.stopRinging,
                        style: FilledButton.styleFrom(
                          backgroundColor: WizardColors.coralError,
                          foregroundColor: WizardColors.obsidian,
                        ),
                        child: const Text('Stop'),
                      ),
                    ),
                  ),
                ],
                if (client.agentUsage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'OMARCHY AI USAGE TODAY',
                                  style: TextStyle(
                                    color: WizardColors.textMuted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => client.refreshAgentUsage(force: true),
                                child: Icon(Icons.refresh_rounded, size: 16, color: WizardColors.cyanArcane),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: client.agentUsage.take(3).map((u) {
                              final firstLimit = u.limits.isNotEmpty ? u.limits.first : null;
                              final quotaStr = firstLimit != null
                                  ? ' · ${firstLimit.percent.round()}%'
                                  : '';
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: WizardColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${u.name}: ${u.todayPrompts} prompts$quotaStr',
                                  style: TextStyle(
                                    color: WizardColors.textPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (client.lastError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: WizardColors.coralError.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: WizardColors.coralError.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: WizardColors.coralError,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            client.lastError!,
                            style: TextStyle(
                              color: WizardColors.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildSpellControlsCard(client),
                const SizedBox(height: 12),
                QuickCastBar(
                  onSelectSpell: (preset) {
                    _promptController.text = preset;
                    _promptController.selection = TextSelection.fromPosition(
                      TextPosition(offset: preset.length),
                    );
                    _promptFocus.requestFocus();
                  },
                ),
                const SizedBox(height: 12),
                _buildPromptComposer(),
                if (activeTask != null) ...[
                  const SizedBox(height: 16),
                  _buildActiveTaskCard(client, activeTask),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpellControlsCard(BridgeClient client) {
    final agents = client.hostStatus.availableAgents;
    final baseWorkspaces = client.hostStatus.workspaces;
    final workspaces = baseWorkspaces.contains(client.selectedWorkspace)
        ? baseWorkspaces
        : [client.selectedWorkspace, ...baseWorkspaces];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SPELL PARAMETERS',
              style: TextStyle(
                color: WizardColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DropdownPill<String>(
                    label: 'Agent',
                    value: agents.contains(client.selectedAgent)
                        ? client.selectedAgent
                        : agents.first,
                    items: agents,
                    onChanged: (v) {
                      if (v != null) client.setSelectedAgent(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DropdownPill<String>(
                    label: 'Mode',
                    value: client.selectedMode,
                    items: const ['auto', 'accept-edits', 'plan'],
                    onChanged: (v) {
                      if (v != null) client.setSelectedMode(v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DropdownPill<String>(
                    label: 'Effort',
                    value: client.selectedEffort,
                    items: const ['low', 'medium', 'high'],
                    onChanged: (v) {
                      if (v != null) client.setSelectedEffort(v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DropdownPill<String>(
              label: 'Workspace',
              value: workspaces.contains(client.selectedWorkspace)
                  ? client.selectedWorkspace
                  : workspaces.first,
              items: workspaces,
              onChanged: (v) {
                if (v != null) client.setSelectedWorkspace(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptComposer() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_replyConversationId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.reply_rounded,
                      size: 16,
                      color: WizardColors.cyanArcane,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Continuing conversation $_replyConversationId',
                        style: TextStyle(
                          color: WizardColors.cyanArcane,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _replyConversationId = null),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: WizardColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _promptController,
              focusNode: _promptFocus,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: TextStyle(color: WizardColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Command your Omarchy AI agent...',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _cast,
              style: FilledButton.styleFrom(
                backgroundColor: WizardColors.violetArcane,
                foregroundColor: WizardColors.obsidian,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text(
                'Cast Spell',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTaskCard(BridgeClient client, AgentTask task) {
    final Color statusColor = switch (task.status) {
      TaskStatus.running => WizardColors.violetArcane,
      TaskStatus.completed => WizardColors.emeraldSage,
      TaskStatus.failed => WizardColors.coralError,
      TaskStatus.cancelled => WizardColors.goldStarlight,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${task.status.displayLabel} • ${task.agent}',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (task.status == TaskStatus.running)
                  TextButton.icon(
                    onPressed: () => client.cancelActiveSpell(task.id),
                    icon: Icon(
                      Icons.stop_circle_outlined,
                      size: 18,
                      color: WizardColors.coralError,
                    ),
                    label: Text(
                      'Dispel',
                      style: TextStyle(
                        color: WizardColors.coralError,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (task.conversationId != null)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _replyConversationId = task.conversationId);
                      _promptFocus.requestFocus();
                    },
                    icon: Icon(
                      Icons.reply_rounded,
                      size: 18,
                      color: WizardColors.cyanArcane,
                    ),
                    label: Text(
                      'Follow Up',
                      style: TextStyle(
                        color: WizardColors.cyanArcane,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              task.prompt,
              style: TextStyle(
                color: WizardColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            SpellLogView(task: task),
          ],
        ),
      ),
    );
  }
}

class _DropdownPill<T> extends StatelessWidget {
  const _DropdownPill({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: WizardColors.midnight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WizardColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: WizardColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              dropdownColor: WizardColors.surfaceElevated,
              iconEnabledColor: WizardColors.cyanArcane,
              style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
                color: WizardColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(
                        item.toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickToolTile extends StatelessWidget {
  const _QuickToolTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WizardColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: WizardColors.borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: accent),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WizardColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolMenuTile extends StatelessWidget {
  const _ToolMenuTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: accent, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: WizardColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: WizardColors.textMuted),
      onTap: onTap,
    );
  }
}
