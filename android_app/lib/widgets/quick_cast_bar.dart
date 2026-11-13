import 'package:material_ui/material_ui.dart';

import '../theme/wizard_theme.dart';

class QuickCastBar extends StatelessWidget {
  const QuickCastBar({
    super.key,
    required this.onSelectSpell,
  });

  final ValueChanged<String> onSelectSpell;

  static const List<(String label, String prompt)> _presets = [
    ('✨ Git Status', 'Check git status and summarize recent uncommitted changes.'),
    ('🧪 Run Tests', 'Run the project test suite and fix any failing tests.'),
    ('🔍 Code Review', 'Review recent commits for bugs, edge cases, and cleanup.'),
    ('🐧 Omarchy Health', 'Check system status, disk space, and failed systemd units.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, prompt) = _presets[index];
          return ActionChip(
            label: Text(
              label,
              style: const TextStyle(
                color: WizardColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: WizardColors.surfaceElevated,
            side: const BorderSide(color: WizardColors.borderSubtle),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onPressed: () => onSelectSpell(prompt),
          );
        },
      ),
    );
  }
}
