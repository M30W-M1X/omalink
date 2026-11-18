import 'package:material_ui/material_ui.dart';

import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.state,
    required this.hostname,
    required this.osVersion,
    required this.onTap,
  });

  final BridgeConnectionState state;
  final String hostname;
  final String osVersion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color dotColor, String label) = switch (state) {
      BridgeConnectionState.connected => (
          WizardColors.emeraldSage,
          '$hostname • Omarchy $osVersion'
        ),
      BridgeConnectionState.connecting => (
          WizardColors.goldStarlight,
          'Connecting to Omarchy...'
        ),
      BridgeConnectionState.disconnected => (
          WizardColors.coralError,
          'Bridge Offline'
        ),
      BridgeConnectionState.demo => (
          WizardColors.cyanArcane,
          'Demo Familiar Mode'
        ),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: WizardColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dotColor.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.7),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: WizardColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
