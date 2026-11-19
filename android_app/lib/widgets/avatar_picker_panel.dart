import 'package:material_ui/material_ui.dart';

import '../models/wizard_avatar.dart';
import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';
import 'arcane_wizard_mascot.dart';

class AvatarPickerPanel extends StatelessWidget {
  const AvatarPickerPanel({
    super.key,
    required this.client,
    this.showHeader = true,
  });

  final BridgeClient client;
  final bool showHeader;

  Future<void> _applyIcon(BuildContext context, WizardAvatarStyle style) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await client.setLauncherIcon(style);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Android app icon set to ${style.label}! Your launcher will refresh shortly.'
              : 'Could not switch Android launcher icon on this device.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = client.avatarStyle;
    final activeIcon = client.launcherIcon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'MASCOT AVATAR & APP ICON',
                  style: TextStyle(
                    color: WizardColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                selected.label,
                style: TextStyle(
                  color: WizardColors.cyanArcane,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap an avatar to animate it on your Home screen, or apply it as your Android launcher icon.',
            style: TextStyle(color: WizardColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 102,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: WizardAvatarStyle.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final style = WizardAvatarStyle.values[index];
              final isSelected = style == selected;
              final isLauncher = style == activeIcon;

              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => client.setAvatarStyle(style),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 96,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? WizardColors.violetArcane.withValues(alpha: 0.2)
                        : WizardColors.midnight,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? WizardColors.cyanArcane
                          : WizardColors.borderSubtle,
                      width: isSelected ? 1.8 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          WizardAvatarThumbnail(style: style, size: 54),
                          if (isLauncher)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: WizardColors.emeraldSage,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: WizardColors.surfaceCard,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.apps_rounded,
                                  size: 11,
                                  color: WizardColors.obsidian,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        style.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected
                              ? WizardColors.cyanArcane
                              : WizardColors.textPrimary,
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: selected == activeIcon
                    ? null
                    : () => _applyIcon(context, selected),
                icon: Icon(
                  selected == activeIcon
                      ? Icons.check_circle_outline_rounded
                      : Icons.app_shortcut_rounded,
                  size: 18,
                ),
                label: Text(
                  selected == activeIcon
                      ? 'Active Android App Icon'
                      : 'Set "${selected.label}" as App Icon',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
