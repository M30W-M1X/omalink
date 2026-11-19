enum WizardAvatarStyle {
  classic(
    id: 'classic',
    label: 'Arcane Agy',
    subtitle: 'Original animated vector wizard',
    assetPath: null,
  ),
  animeGirl(
    id: 'anime_girl',
    label: 'Anime Wizard',
    subtitle: 'Cute anime mage with glowing crystal orb',
    assetPath: 'assets/avatars/anime_wizard_girl.png',
  ),
  arcaneCat(
    id: 'arcane_cat',
    label: 'Arcane Cat',
    subtitle: 'Familiar black cat in rune wizard hat',
    assetPath: 'assets/avatars/arcane_cat.png',
  ),
  cyberMage(
    id: 'cyber_mage',
    label: 'Cyber-Mage',
    subtitle: 'Shadow-hooded mage with neon staff',
    assetPath: 'assets/avatars/cyber_mage.png',
  ),
  astralSpirit(
    id: 'astral_spirit',
    label: 'Astral Owl',
    subtitle: 'Floating celestial owl-wisp familiar',
    assetPath: 'assets/avatars/astral_spirit.png',
  );

  const WizardAvatarStyle({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.assetPath,
  });

  final String id;
  final String label;
  final String subtitle;
  final String? assetPath;

  static WizardAvatarStyle fromId(String? raw) {
    for (final style in values) {
      if (style.id == raw) return style;
    }
    return WizardAvatarStyle.classic;
  }
}
