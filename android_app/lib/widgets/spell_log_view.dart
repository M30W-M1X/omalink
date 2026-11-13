import 'package:material_ui/material_ui.dart';

import '../models/agent_task.dart';
import '../theme/wizard_theme.dart';

class SpellLogView extends StatelessWidget {
  const SpellLogView({
    super.key,
    required this.task,
  });

  final AgentTask task;

  @override
  Widget build(BuildContext context) {
    if (task.events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Waiting for arcane output...',
            style: TextStyle(color: WizardColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: task.events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ev = task.events[index];
        final (Color badgeColor, IconData icon) = switch (ev.kind) {
          'result' => (WizardColors.emeraldSage, Icons.auto_awesome),
          'error' || 'stderr' => (WizardColors.coralError, Icons.warning_amber_rounded),
          'tool' || 'tool_use' => (WizardColors.goldStarlight, Icons.build_rounded),
          'system' => (WizardColors.textMuted, Icons.terminal_rounded),
          _ => (WizardColors.cyanArcane, Icons.bolt_rounded),
        };

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: WizardColors.midnight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: badgeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ev.text,
                  style: const TextStyle(
                    color: WizardColors.textPrimary,
                    fontSize: 13,
                    height: 1.35,
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
