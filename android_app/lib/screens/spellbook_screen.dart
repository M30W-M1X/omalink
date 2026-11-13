import 'package:material_ui/material_ui.dart';

import '../models/agent_task.dart';
import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';
import '../widgets/spell_log_view.dart';

class SpellbookScreen extends StatelessWidget {
  const SpellbookScreen({
    super.key,
    required this.client,
    required this.onInspectInHome,
  });

  final BridgeClient client;
  final VoidCallback onInspectInHome;

  @override
  Widget build(BuildContext context) {
    final tasks = client.tasks;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spellbook',
                  style: TextStyle(
                    color: WizardColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Recent tasks cast on Omarchy',
                  style: TextStyle(
                    color: WizardColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Your spellbook is empty.\nCast your first task from the Wizard tab!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: WizardColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _SpellHistoryCard(
                        task: task,
                        onTap: () => _openDetails(context, task),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetails(BuildContext context, AgentTask task) {
    client.selectTask(task.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WizardColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  task.prompt,
                  style: const TextStyle(
                    color: WizardColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${task.agent} • ${task.mode}/${task.effort} • ${task.cwd}',
                  style: const TextStyle(
                    color: WizardColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                SpellLogView(task: task),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onInspectInHome();
                        },
                        child: const Text('Open on Stage'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          client.castSpell(task.prompt);
                          onInspectInHome();
                        },
                        child: const Text('Recast Spell'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SpellHistoryCard extends StatelessWidget {
  const _SpellHistoryCard({
    required this.task,
    required this.onTap,
  });

  final AgentTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (task.status) {
      TaskStatus.running => (WizardColors.violetArcane, Icons.auto_awesome),
      TaskStatus.completed => (WizardColors.emeraldSage, Icons.check_circle_outline),
      TaskStatus.failed => (WizardColors.coralError, Icons.error_outline),
      TaskStatus.cancelled => (WizardColors.goldStarlight, Icons.cancel_outlined),
    };

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WizardColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (task.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WizardColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${task.status.displayLabel} • ${task.agent}'
                      '${task.durationSeconds != null ? ' • ${task.durationSeconds}s' : ''}',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
