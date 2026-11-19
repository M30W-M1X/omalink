import 'package:material_ui/material_ui.dart';

class WizardPalette {
  const WizardPalette({
    required this.slug,
    required this.name,
    required this.isLight,
    required this.obsidian,
    required this.midnight,
    required this.surfaceCard,
    required this.surfaceElevated,
    required this.borderSubtle,
    required this.cyanArcane,
    required this.violetArcane,
    required this.emeraldSage,
    required this.goldStarlight,
    required this.coralError,
    required this.textPrimary,
    required this.textMuted,
    required this.ansiBlack,
    required this.ansiRed,
    required this.ansiGreen,
    required this.ansiYellow,
    required this.ansiBlue,
    required this.ansiMagenta,
    required this.ansiCyan,
    required this.ansiWhite,
    required this.ansiBrightBlack,
    required this.ansiBrightRed,
    required this.ansiBrightGreen,
    required this.ansiBrightYellow,
    required this.ansiBrightBlue,
    required this.ansiBrightMagenta,
    required this.ansiBrightCyan,
    required this.ansiBrightWhite,
  });

  final String slug;
  final String name;
  final bool isLight;

  final Color obsidian;
  final Color midnight;
  final Color surfaceCard;
  final Color surfaceElevated;
  final Color borderSubtle;

  final Color cyanArcane;
  final Color violetArcane;
  final Color emeraldSage;
  final Color goldStarlight;
  final Color coralError;

  final Color textPrimary;
  final Color textMuted;

  final Color ansiBlack;
  final Color ansiRed;
  final Color ansiGreen;
  final Color ansiYellow;
  final Color ansiBlue;
  final Color ansiMagenta;
  final Color ansiCyan;
  final Color ansiWhite;
  final Color ansiBrightBlack;
  final Color ansiBrightRed;
  final Color ansiBrightGreen;
  final Color ansiBrightYellow;
  final Color ansiBrightBlue;
  final Color ansiBrightMagenta;
  final Color ansiBrightCyan;
  final Color ansiBrightWhite;

  static const WizardPalette tokyoNight = WizardPalette(
    slug: 'tokyo-night',
    name: 'Tokyo Night',
    isLight: false,
    obsidian: Color(0xFF0D0F18),
    midnight: Color(0xFF151828),
    surfaceCard: Color(0xFF1B2034),
    surfaceElevated: Color(0xFF232942),
    borderSubtle: Color(0xFF2F3758),
    cyanArcane: Color(0xFF7DCFFF),
    violetArcane: Color(0xFFBB9AF7),
    emeraldSage: Color(0xFF9ECE6A),
    goldStarlight: Color(0xFFE0AF68),
    coralError: Color(0xFFF7768E),
    textPrimary: Color(0xFFE2E8FA),
    textMuted: Color(0xFF8B95B8),
    ansiBlack: Color(0xFF15161E),
    ansiRed: Color(0xFFF7768E),
    ansiGreen: Color(0xFF9ECE6A),
    ansiYellow: Color(0xFFE0AF68),
    ansiBlue: Color(0xFF7AA2F7),
    ansiMagenta: Color(0xFFBB9AF7),
    ansiCyan: Color(0xFF7DCFFF),
    ansiWhite: Color(0xFFA9B1D6),
    ansiBrightBlack: Color(0xFF414868),
    ansiBrightRed: Color(0xFFF7768E),
    ansiBrightGreen: Color(0xFF9ECE6A),
    ansiBrightYellow: Color(0xFFE0AF68),
    ansiBrightBlue: Color(0xFF7AA2F7),
    ansiBrightMagenta: Color(0xFFBB9AF7),
    ansiBrightCyan: Color(0xFF7DCFFF),
    ansiBrightWhite: Color(0xFFC0CAF5),
  );

  static const WizardPalette nord = WizardPalette(
    slug: 'nord',
    name: 'Nord',
    isLight: false,
    obsidian: Color(0xFF191C23),
    midnight: Color(0xFF222730),
    surfaceCard: Color(0xFF2E3440),
    surfaceElevated: Color(0xFF3B4252),
    borderSubtle: Color(0xFF4C566A),
    cyanArcane: Color(0xFF88C0D0),
    violetArcane: Color(0xFF81A1C1),
    emeraldSage: Color(0xFFA3BE8C),
    goldStarlight: Color(0xFFEBCB8B),
    coralError: Color(0xFFBF616A),
    textPrimary: Color(0xFFD8DEE9),
    textMuted: Color(0xFFADB5C4),
    ansiBlack: Color(0xFF2E3440),
    ansiRed: Color(0xFFBF616A),
    ansiGreen: Color(0xFFA3BE8C),
    ansiYellow: Color(0xFFEBCB8B),
    ansiBlue: Color(0xFF81A1C1),
    ansiMagenta: Color(0xFFB48EAD),
    ansiCyan: Color(0xFF88C0D0),
    ansiWhite: Color(0xFFD8DEE9),
    ansiBrightBlack: Color(0xFF4C566A),
    ansiBrightRed: Color(0xFFBF616A),
    ansiBrightGreen: Color(0xFFA3BE8C),
    ansiBrightYellow: Color(0xFFEBCB8B),
    ansiBrightBlue: Color(0xFF81A1C1),
    ansiBrightMagenta: Color(0xFFB48EAD),
    ansiBrightCyan: Color(0xFF8FBCBB),
    ansiBrightWhite: Color(0xFFECEFF4),
  );

  static const WizardPalette everforest = WizardPalette(
    slug: 'everforest',
    name: 'Everforest',
    isLight: false,
    obsidian: Color(0xFF181D20),
    midnight: Color(0xFF21272C),
    surfaceCard: Color(0xFF2D353B),
    surfaceElevated: Color(0xFF343F44),
    borderSubtle: Color(0xFF475258),
    cyanArcane: Color(0xFF83C092),
    violetArcane: Color(0xFF7FBBB3),
    emeraldSage: Color(0xFFA7C080),
    goldStarlight: Color(0xFFDBBC7F),
    coralError: Color(0xFFE67E80),
    textPrimary: Color(0xFFD3C6AA),
    textMuted: Color(0xFF9DA9A0),
    ansiBlack: Color(0xFF2D353B),
    ansiRed: Color(0xFFE67E80),
    ansiGreen: Color(0xFFA7C080),
    ansiYellow: Color(0xFFDBBC7F),
    ansiBlue: Color(0xFF7FBBB3),
    ansiMagenta: Color(0xFFD699B6),
    ansiCyan: Color(0xFF83C092),
    ansiWhite: Color(0xFFD3C6AA),
    ansiBrightBlack: Color(0xFF475258),
    ansiBrightRed: Color(0xFFE67E80),
    ansiBrightGreen: Color(0xFFA7C080),
    ansiBrightYellow: Color(0xFFDBBC7F),
    ansiBrightBlue: Color(0xFF7FBBB3),
    ansiBrightMagenta: Color(0xFFD699B6),
    ansiBrightCyan: Color(0xFF83C092),
    ansiBrightWhite: Color(0xFFD3C6AA),
  );

  static const WizardPalette catppuccin = WizardPalette(
    slug: 'catppuccin',
    name: 'Catppuccin',
    isLight: false,
    obsidian: Color(0xFF11111B),
    midnight: Color(0xFF181825),
    surfaceCard: Color(0xFF1E1E2E),
    surfaceElevated: Color(0xFF313244),
    borderSubtle: Color(0xFF45475A),
    cyanArcane: Color(0xFF89DCEB),
    violetArcane: Color(0xFFCBA6F7),
    emeraldSage: Color(0xFFA6E3A1),
    goldStarlight: Color(0xFFF9E2AF),
    coralError: Color(0xFFF38BA8),
    textPrimary: Color(0xFFCDD6F4),
    textMuted: Color(0xFFA6ADC8),
    ansiBlack: Color(0xFF1E1E2E),
    ansiRed: Color(0xFFF38BA8),
    ansiGreen: Color(0xFFA6E3A1),
    ansiYellow: Color(0xFFF9E2AF),
    ansiBlue: Color(0xFF89B4FA),
    ansiMagenta: Color(0xFFCBA6F7),
    ansiCyan: Color(0xFF89DCEB),
    ansiWhite: Color(0xFFCDD6F4),
    ansiBrightBlack: Color(0xFF585B70),
    ansiBrightRed: Color(0xFFF38BA8),
    ansiBrightGreen: Color(0xFFA6E3A1),
    ansiBrightYellow: Color(0xFFF9E2AF),
    ansiBrightBlue: Color(0xFF89B4FA),
    ansiBrightMagenta: Color(0xFFCBA6F7),
    ansiBrightCyan: Color(0xFF94E2D5),
    ansiBrightWhite: Color(0xFFCDD6F4),
  );

  static const WizardPalette catppuccinLatte = WizardPalette(
    slug: 'catppuccin-latte',
    name: 'Catppuccin Latte',
    isLight: true,
    obsidian: Color(0xFFEFF1F5),
    midnight: Color(0xFFE3E4E8),
    surfaceCard: Color(0xFFF8F9FC),
    surfaceElevated: Color(0xFFDCE0E8),
    borderSubtle: Color(0xFFACB0BE),
    cyanArcane: Color(0xFF179299),
    violetArcane: Color(0xFF1E66F5),
    emeraldSage: Color(0xFF40A02B),
    goldStarlight: Color(0xFFDF8E1D),
    coralError: Color(0xFFD20F39),
    textPrimary: Color(0xFF4C4F69),
    textMuted: Color(0xFF6C6F85),
    ansiBlack: Color(0xFF4C4F69),
    ansiRed: Color(0xFFD20F39),
    ansiGreen: Color(0xFF40A02B),
    ansiYellow: Color(0xFFDF8E1D),
    ansiBlue: Color(0xFF1E66F5),
    ansiMagenta: Color(0xFFEA76CB),
    ansiCyan: Color(0xFF179299),
    ansiWhite: Color(0xFFEFF1F5),
    ansiBrightBlack: Color(0xFF6C6F85),
    ansiBrightRed: Color(0xFFD20F39),
    ansiBrightGreen: Color(0xFF40A02B),
    ansiBrightYellow: Color(0xFFDF8E1D),
    ansiBrightBlue: Color(0xFF1E66F5),
    ansiBrightMagenta: Color(0xFFEA76CB),
    ansiBrightCyan: Color(0xFF179299),
    ansiBrightWhite: Color(0xFFFFFFFF),
  );

  static const WizardPalette gruvbox = WizardPalette(
    slug: 'gruvbox',
    name: 'Gruvbox',
    isLight: false,
    obsidian: Color(0xFF1D2021),
    midnight: Color(0xFF282828),
    surfaceCard: Color(0xFF32302F),
    surfaceElevated: Color(0xFF3C3836),
    borderSubtle: Color(0xFF504945),
    cyanArcane: Color(0xFF8EC07C),
    violetArcane: Color(0xFFD3869B),
    emeraldSage: Color(0xFFB8BB26),
    goldStarlight: Color(0xFFFABD2F),
    coralError: Color(0xFFFB4934),
    textPrimary: Color(0xFFEBDBB2),
    textMuted: Color(0xFFA89984),
    ansiBlack: Color(0xFF282828),
    ansiRed: Color(0xFFCC241D),
    ansiGreen: Color(0xFF98971A),
    ansiYellow: Color(0xFFD79921),
    ansiBlue: Color(0xFF458588),
    ansiMagenta: Color(0xFFB16286),
    ansiCyan: Color(0xFF689D6A),
    ansiWhite: Color(0xFFEBDBB2),
    ansiBrightBlack: Color(0xFF665C54),
    ansiBrightRed: Color(0xFFFB4934),
    ansiBrightGreen: Color(0xFFB8BB26),
    ansiBrightYellow: Color(0xFFFABD2F),
    ansiBrightBlue: Color(0xFF83A598),
    ansiBrightMagenta: Color(0xFFD3869B),
    ansiBrightCyan: Color(0xFF8EC07C),
    ansiBrightWhite: Color(0xFFFBF1C7),
  );

  static const WizardPalette rosePine = WizardPalette(
    slug: 'rose-pine',
    name: 'Rose Pine',
    isLight: false,
    obsidian: Color(0xFF12101E),
    midnight: Color(0xFF191724),
    surfaceCard: Color(0xFF1F1D2E),
    surfaceElevated: Color(0xFF26233A),
    borderSubtle: Color(0xFF403D52),
    cyanArcane: Color(0xFF9CCFD8),
    violetArcane: Color(0xFFC4A7E7),
    emeraldSage: Color(0xFF31748F),
    goldStarlight: Color(0xFFF6C177),
    coralError: Color(0xFFEB6F92),
    textPrimary: Color(0xFFE0DEF4),
    textMuted: Color(0xFF908CAA),
    ansiBlack: Color(0xFF191724),
    ansiRed: Color(0xFFEB6F92),
    ansiGreen: Color(0xFF9CCFD8),
    ansiYellow: Color(0xFFF6C177),
    ansiBlue: Color(0xFF31748F),
    ansiMagenta: Color(0xFFC4A7E7),
    ansiCyan: Color(0xFFEBBCBA),
    ansiWhite: Color(0xFFE0DEF4),
    ansiBrightBlack: Color(0xFF6E6A86),
    ansiBrightRed: Color(0xFFEB6F92),
    ansiBrightGreen: Color(0xFF9CCFD8),
    ansiBrightYellow: Color(0xFFF6C177),
    ansiBrightBlue: Color(0xFF31748F),
    ansiBrightMagenta: Color(0xFFC4A7E7),
    ansiBrightCyan: Color(0xFFEBBCBA),
    ansiBrightWhite: Color(0xFFE0DEF4),
  );

  static const WizardPalette kanagawa = WizardPalette(
    slug: 'kanagawa',
    name: 'Kanagawa',
    isLight: false,
    obsidian: Color(0xFF16161D),
    midnight: Color(0xFF1F1F28),
    surfaceCard: Color(0xFF2A2A37),
    surfaceElevated: Color(0xFF363646),
    borderSubtle: Color(0xFF54546D),
    cyanArcane: Color(0xFF7FB4CA),
    violetArcane: Color(0xFF957FB8),
    emeraldSage: Color(0xFF98BB6C),
    goldStarlight: Color(0xFFE6C384),
    coralError: Color(0xFFE82424),
    textPrimary: Color(0xFFDCD7BA),
    textMuted: Color(0xFF9E9B93),
    ansiBlack: Color(0xFF1F1F28),
    ansiRed: Color(0xFFC34043),
    ansiGreen: Color(0xFF76946A),
    ansiYellow: Color(0xFFC0A36E),
    ansiBlue: Color(0xFF7E9CD8),
    ansiMagenta: Color(0xFF957FB8),
    ansiCyan: Color(0xFF6A9589),
    ansiWhite: Color(0xFFDCD7BA),
    ansiBrightBlack: Color(0xFF727169),
    ansiBrightRed: Color(0xFFE82424),
    ansiBrightGreen: Color(0xFF98BB6C),
    ansiBrightYellow: Color(0xFFE6C384),
    ansiBrightBlue: Color(0xFF7FB4CA),
    ansiBrightMagenta: Color(0xFF938AA9),
    ansiBrightCyan: Color(0xFF7AA89F),
    ansiBrightWhite: Color(0xFFDCD7BA),
  );

  static const WizardPalette matteBlack = WizardPalette(
    slug: 'matte-black',
    name: 'Matte Black',
    isLight: false,
    obsidian: Color(0xFF090909),
    midnight: Color(0xFF121212),
    surfaceCard: Color(0xFF1A1A1A),
    surfaceElevated: Color(0xFF262626),
    borderSubtle: Color(0xFF383838),
    cyanArcane: Color(0xFFEAEAEA),
    violetArcane: Color(0xFFD4AF37),
    emeraldSage: Color(0xFF8FBC8F),
    goldStarlight: Color(0xFFE6C27A),
    coralError: Color(0xFFD35F5F),
    textPrimary: Color(0xFFEAEAEA),
    textMuted: Color(0xFF9A9A9A),
    ansiBlack: Color(0xFF121212),
    ansiRed: Color(0xFFD35F5F),
    ansiGreen: Color(0xFF8FBC8F),
    ansiYellow: Color(0xFFE6C27A),
    ansiBlue: Color(0xFF8AB4F8),
    ansiMagenta: Color(0xFFC58AF9),
    ansiCyan: Color(0xFF78D9EC),
    ansiWhite: Color(0xFFEAEAEA),
    ansiBrightBlack: Color(0xFF555555),
    ansiBrightRed: Color(0xFFD35F5F),
    ansiBrightGreen: Color(0xFF8FBC8F),
    ansiBrightYellow: Color(0xFFE6C27A),
    ansiBrightBlue: Color(0xFF8AB4F8),
    ansiBrightMagenta: Color(0xFFC58AF9),
    ansiBrightCyan: Color(0xFF78D9EC),
    ansiBrightWhite: Color(0xFFFFFFFF),
  );

  static const List<WizardPalette> presets = [
    tokyoNight,
    nord,
    everforest,
    catppuccin,
    catppuccinLatte,
    gruvbox,
    rosePine,
    kanagawa,
    matteBlack,
  ];

  static String normalizeSlug(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static WizardPalette byName(String raw) {
    final slug = normalizeSlug(raw);
    for (final p in presets) {
      if (p.slug == slug) return p;
    }
    return tokyoNight;
  }

  static Color? tryParseHex(dynamic raw) {
    if (raw is! String) return null;
    final cleaned = raw.trim().replaceFirst('#', '');
    if (cleaned.length == 6) {
      final value = int.tryParse('FF$cleaned', radix: 16);
      return value == null ? null : Color(value);
    }
    if (cleaned.length == 8) {
      final value = int.tryParse(cleaned, radix: 16);
      return value == null ? null : Color(value);
    }
    return null;
  }

  static String _toHex(Color c) {
    final r = (c.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  factory WizardPalette.fromOmarchyJson(Map<String, dynamic> json) {
    final slug = normalizeSlug(
      json['slug']?.toString() ?? json['name']?.toString() ?? 'tokyo-night',
    );
    final name = json['name']?.toString().trim().isNotEmpty == true
        ? json['name'].toString().trim()
        : byName(slug).name;
    final fallback = byName(slug);
    final rawColors = json['colors'];
    if (rawColors is! Map || rawColors.isEmpty) {
      return fallback;
    }

    Color pick(List<String> keys, Color def) {
      for (final k in keys) {
        final parsed = tryParseHex(rawColors[k]);
        if (parsed != null) return parsed;
      }
      return def;
    }

    final isLight = json['mode']?.toString().toLowerCase() == 'light';

    final bg = pick(['background'], fallback.surfaceCard);
    final darkBg = pick(['dark_background', 'background'], fallback.midnight);
    final darkerBg = pick(['darker_background', 'dark_background', 'background'], fallback.obsidian);
    final lighterBg = pick(['lighter_background', 'selection', 'background'], fallback.surfaceElevated);
    final mutedBorder = pick(['muted', 'selection'], fallback.borderSubtle);

    final fg = pick(['foreground', 'bright_foreground'], fallback.textPrimary);
    final mutedFg = pick(['light_foreground', 'dark_foreground'], fallback.textMuted);

    final accent = pick(['accent', 'magenta', 'blue'], fallback.violetArcane);
    final cyan = pick(['cyan', 'bright_cyan', 'blue', 'accent'], fallback.cyanArcane);
    final green = pick(['green', 'bright_green'], fallback.emeraldSage);
    final yellow = pick(['yellow', 'orange', 'bright_yellow'], fallback.goldStarlight);
    final red = pick(['red', 'bright_red'], fallback.coralError);
    final blue = pick(['blue', 'accent'], fallback.ansiBlue);
    final magenta = pick(['magenta', 'accent'], fallback.ansiMagenta);

    final obsidian = isLight ? bg : darkerBg;
    final midnight = isLight ? darkBg : darkBg;
    final surfaceCard = isLight
        ? (Color.lerp(bg, Colors.white, 0.55) ?? bg)
        : bg;
    final surfaceElevated = isLight ? lighterBg : lighterBg;

    return WizardPalette(
      slug: slug.isEmpty ? fallback.slug : slug,
      name: name,
      isLight: isLight,
      obsidian: obsidian,
      midnight: midnight,
      surfaceCard: surfaceCard,
      surfaceElevated: surfaceElevated,
      borderSubtle: mutedBorder,
      cyanArcane: cyan,
      violetArcane: accent,
      emeraldSage: green,
      goldStarlight: yellow,
      coralError: red,
      textPrimary: fg,
      textMuted: mutedFg,
      ansiBlack: isLight ? fg : bg,
      ansiRed: red,
      ansiGreen: green,
      ansiYellow: yellow,
      ansiBlue: blue,
      ansiMagenta: magenta,
      ansiCyan: cyan,
      ansiWhite: isLight ? bg : fg,
      ansiBrightBlack: mutedBorder,
      ansiBrightRed: pick(['bright_red', 'red'], red),
      ansiBrightGreen: pick(['bright_green', 'green'], green),
      ansiBrightYellow: pick(['bright_yellow', 'yellow'], yellow),
      ansiBrightBlue: pick(['bright_blue', 'blue'], blue),
      ansiBrightMagenta: pick(['bright_magenta', 'magenta'], magenta),
      ansiBrightCyan: pick(['bright_cyan', 'cyan'], cyan),
      ansiBrightWhite: pick(['bright_foreground', 'foreground'], fg),
    );
  }

  Map<String, dynamic> toOmarchyJson() {
    return {
      'slug': slug,
      'name': name,
      'mode': isLight ? 'light' : 'dark',
      'colors': {
        'accent': _toHex(violetArcane),
        'selection': _toHex(surfaceElevated),
        'muted': _toHex(borderSubtle),
        'background': _toHex(isLight ? obsidian : surfaceCard),
        'dark_background': _toHex(midnight),
        'darker_background': _toHex(obsidian),
        'lighter_background': _toHex(surfaceElevated),
        'foreground': _toHex(textPrimary),
        'light_foreground': _toHex(textMuted),
        'bright_foreground': _toHex(ansiBrightWhite),
        'red': _toHex(ansiRed),
        'yellow': _toHex(ansiYellow),
        'green': _toHex(ansiGreen),
        'cyan': _toHex(ansiCyan),
        'blue': _toHex(ansiBlue),
        'magenta': _toHex(ansiMagenta),
        'bright_red': _toHex(ansiBrightRed),
        'bright_yellow': _toHex(ansiBrightYellow),
        'bright_green': _toHex(ansiBrightGreen),
        'bright_cyan': _toHex(ansiBrightCyan),
        'bright_blue': _toHex(ansiBrightBlue),
        'bright_magenta': _toHex(ansiBrightMagenta),
      },
    };
  }
}

class WizardColors {
  WizardColors._();

  static WizardPalette _active = WizardPalette.tokyoNight;
  static WizardPalette get active => _active;

  static void apply(WizardPalette palette) {
    _active = palette;
  }

  static Color get obsidian => _active.obsidian;
  static Color get midnight => _active.midnight;
  static Color get surfaceCard => _active.surfaceCard;
  static Color get surfaceElevated => _active.surfaceElevated;
  static Color get borderSubtle => _active.borderSubtle;

  static Color get cyanArcane => _active.cyanArcane;
  static Color get violetArcane => _active.violetArcane;
  static Color get emeraldSage => _active.emeraldSage;
  static Color get goldStarlight => _active.goldStarlight;
  static Color get coralError => _active.coralError;

  static Color get textPrimary => _active.textPrimary;
  static Color get textMuted => _active.textMuted;
}

class WizardTheme {
  WizardTheme._();

  static ThemeData darkTheme() => fromPalette(WizardColors.active);

  static ThemeData fromPalette(WizardPalette palette) {
    final brightness = palette.isLight ? Brightness.light : Brightness.dark;
    final onAccent = palette.isLight ? Colors.white : palette.obsidian;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.violetArcane,
      onPrimary: onAccent,
      secondary: palette.cyanArcane,
      onSecondary: onAccent,
      tertiary: palette.emeraldSage,
      onTertiary: onAccent,
      surface: palette.surfaceCard,
      onSurface: palette.textPrimary,
      error: palette.coralError,
      onError: onAccent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['NotoSymbols', 'NotoSymbols2', 'NotoEmoji'],
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.obsidian,
      cardTheme: CardThemeData(
        color: palette.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.borderSubtle, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontFamilyFallback: const ['NotoSymbols', 'NotoSymbols2', 'NotoEmoji'],
          color: palette.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.midnight,
        hintStyle: TextStyle(color: palette.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.cyanArcane, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.midnight,
        indicatorColor: palette.violetArcane.withValues(alpha: 0.22),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? palette.cyanArcane : palette.textMuted,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? palette.cyanArcane : palette.textMuted,
          );
        }),
      ),
    );
  }
}
