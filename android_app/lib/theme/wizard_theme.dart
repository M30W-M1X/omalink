import 'package:material_ui/material_ui.dart';

class WizardColors {
  WizardColors._();

  // Omarchy Tokyo-Night + Arcane Wizard palette
  static const Color obsidian = Color(0xFF0D0F18);
  static const Color midnight = Color(0xFF151828);
  static const Color surfaceCard = Color(0xFF1B2034);
  static const Color surfaceElevated = Color(0xFF232942);
  static const Color borderSubtle = Color(0xFF2F3758);

  static const Color cyanArcane = Color(0xFF7DCFFF);
  static const Color violetArcane = Color(0xFFBB9AF7);
  static const Color emeraldSage = Color(0xFF9ECE6A);
  static const Color goldStarlight = Color(0xFFE0AF68);
  static const Color coralError = Color(0xFFF7768E);

  static const Color textPrimary = Color(0xFFE2E8FA);
  static const Color textMuted = Color(0xFF8B95B8);
}

class WizardTheme {
  WizardTheme._();

  static ThemeData darkTheme() {
    const scheme = ColorScheme.dark(
      primary: WizardColors.violetArcane,
      onPrimary: WizardColors.obsidian,
      secondary: WizardColors.cyanArcane,
      onSecondary: WizardColors.obsidian,
      tertiary: WizardColors.emeraldSage,
      surface: WizardColors.surfaceCard,
      onSurface: WizardColors.textPrimary,
      error: WizardColors.coralError,
      onError: WizardColors.obsidian,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: WizardColors.obsidian,
      cardTheme: CardThemeData(
        color: WizardColors.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: WizardColors.borderSubtle, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: WizardColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WizardColors.midnight,
        hintStyle: const TextStyle(color: WizardColors.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: WizardColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: WizardColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: WizardColors.cyanArcane, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: WizardColors.midnight,
        indicatorColor: WizardColors.violetArcane.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? WizardColors.cyanArcane
                : WizardColors.textMuted,
          );
        }),
      ),
    );
  }
}
