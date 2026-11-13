import 'package:material_ui/material_ui.dart';

import '../models/agent_task.dart';
import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';
import '../widgets/arcane_wizard_mascot.dart';
import '../widgets/quick_cast_bar.dart';
import '../widgets/spell_log_view.dart';
import '../widgets/status_pill.dart';

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

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final activeTask = client.activeOrSelectedTask;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Omarchy Wizard',
                            style: TextStyle(
                              color: WizardColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Arcane AI Agent Controller',
                            style: TextStyle(
                              color: WizardColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      state: client.connectionState,
                      hostname: client.hostStatus.hostname,
                      osVersion: client.hostStatus.osVersion,
                      onTap: widget.onOpenSettings,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: ArcaneWizardMascot(
                    mood: client.mood,
                    quip: client.wizardQuip,
                    onTap: client.triggerWizardBoop,
                  ),
                ),
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
                        const Icon(
                          Icons.error_outline_rounded,
                          color: WizardColors.coralError,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            client.lastError!,
                            style: const TextStyle(
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
    final workspaces = client.hostStatus.workspaces;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
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
                    const Icon(
                      Icons.reply_rounded,
                      size: 16,
                      color: WizardColors.cyanArcane,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Continuing conversation $_replyConversationId',
                        style: const TextStyle(
                          color: WizardColors.cyanArcane,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _replyConversationId = null),
                      child: const Icon(
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
              style: const TextStyle(color: WizardColors.textPrimary),
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
                    icon: const Icon(
                      Icons.stop_circle_outlined,
                      size: 18,
                      color: WizardColors.coralError,
                    ),
                    label: const Text(
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
                    icon: const Icon(
                      Icons.reply_rounded,
                      size: 18,
                      color: WizardColors.cyanArcane,
                    ),
                    label: const Text(
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
              style: const TextStyle(
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
            style: const TextStyle(
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
              style: const TextStyle(
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
