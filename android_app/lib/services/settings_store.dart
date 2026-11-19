import 'package:shared_preferences/shared_preferences.dart';

class WizardSettings {
  const WizardSettings({
    this.host = '192.168.1.100',
    this.port = 7842,
    this.token = '',
    this.demoMode = true,
    this.notifyOnComplete = true,
    this.defaultMode = 'auto',
    this.defaultEffort = 'high',
    this.relayNotifications = true,
    this.relayCalls = true,
    this.syncOmarchyTheme = true,
    this.themeOverride = 'tokyo-night',
    this.cachedThemeJson = '',
    this.autoSyncClipboard = false,
    this.useTls = false,
    this.tlsFingerprint = '',
    this.tailscaleHost = '',
    this.vitalsNotification = true,
    this.avatarStyle = 'classic',
    this.launcherIcon = 'classic',
  });

  final String host;
  final int port;
  final String token;
  final bool demoMode;
  final bool notifyOnComplete;
  final String defaultMode;
  final String defaultEffort;
  final bool relayNotifications;
  final bool relayCalls;
  final bool syncOmarchyTheme;
  final String themeOverride;
  final String cachedThemeJson;
  final bool autoSyncClipboard;
  final bool useTls;
  final String tlsFingerprint;
  final String tailscaleHost;
  final bool vitalsNotification;
  final String avatarStyle;
  final String launcherIcon;

  String get httpScheme => useTls ? 'https' : 'http';
  String get wsScheme => useTls ? 'wss' : 'ws';

  String get httpBaseUrl => '$httpScheme://$host:$port';
  String get wsUrl => '$wsScheme://$host:$port/ws';
  String get terminalWsUrl => '$wsScheme://$host:$port/ws/terminal';
  String get desktopWsUrl => '$wsScheme://$host:$port/ws/desktop';

  WizardSettings copyWith({
    String? host,
    int? port,
    String? token,
    bool? demoMode,
    bool? notifyOnComplete,
    String? defaultMode,
    String? defaultEffort,
    bool? relayNotifications,
    bool? relayCalls,
    bool? syncOmarchyTheme,
    String? themeOverride,
    String? cachedThemeJson,
    bool? autoSyncClipboard,
    bool? useTls,
    String? tlsFingerprint,
    String? tailscaleHost,
    bool? vitalsNotification,
    String? avatarStyle,
    String? launcherIcon,
  }) {
    return WizardSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      demoMode: demoMode ?? this.demoMode,
      notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
      defaultMode: defaultMode ?? this.defaultMode,
      defaultEffort: defaultEffort ?? this.defaultEffort,
      relayNotifications: relayNotifications ?? this.relayNotifications,
      relayCalls: relayCalls ?? this.relayCalls,
      syncOmarchyTheme: syncOmarchyTheme ?? this.syncOmarchyTheme,
      themeOverride: themeOverride ?? this.themeOverride,
      cachedThemeJson: cachedThemeJson ?? this.cachedThemeJson,
      autoSyncClipboard: autoSyncClipboard ?? this.autoSyncClipboard,
      useTls: useTls ?? this.useTls,
      tlsFingerprint: tlsFingerprint ?? this.tlsFingerprint,
      tailscaleHost: tailscaleHost ?? this.tailscaleHost,
      vitalsNotification: vitalsNotification ?? this.vitalsNotification,
      avatarStyle: avatarStyle ?? this.avatarStyle,
      launcherIcon: launcherIcon ?? this.launcherIcon,
    );
  }
}

class SettingsStore {
  static const _keyHost = 'wizard_host';
  static const _keyPort = 'wizard_port';
  static const _keyToken = 'wizard_token';
  static const _keyDemo = 'wizard_demo';
  static const _keyNotify = 'wizard_notify';
  static const _keyMode = 'wizard_mode';
  static const _keyEffort = 'wizard_effort';
  static const _keyRelayNotif = 'wizard_relay_notifications';
  static const _keyRelayCalls = 'wizard_relay_calls';
  static const _keySyncTheme = 'wizard_sync_omarchy_theme';
  static const _keyThemeOverride = 'wizard_theme_override';
  static const _keyCachedTheme = 'wizard_cached_theme_json';
  static const _keyAutoClip = 'wizard_auto_sync_clipboard';
  static const _keyUseTls = 'wizard_use_tls';
  static const _keyTlsFp = 'wizard_tls_fingerprint';
  static const _keyTailscaleHost = 'wizard_tailscale_host';
  static const _keyVitalsNotif = 'wizard_vitals_notification';
  static const _keyAvatarStyle = 'wizard_avatar_style';
  static const _keyLauncherIcon = 'wizard_launcher_icon';

  Future<WizardSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return WizardSettings(
      host: prefs.getString(_keyHost) ?? '192.168.1.100',
      port: prefs.getInt(_keyPort) ?? 7842,
      token: prefs.getString(_keyToken) ?? '',
      demoMode: prefs.getBool(_keyDemo) ?? true,
      notifyOnComplete: prefs.getBool(_keyNotify) ?? true,
      defaultMode: prefs.getString(_keyMode) ?? 'auto',
      defaultEffort: prefs.getString(_keyEffort) ?? 'high',
      relayNotifications: prefs.getBool(_keyRelayNotif) ?? true,
      relayCalls: prefs.getBool(_keyRelayCalls) ?? true,
      syncOmarchyTheme: prefs.getBool(_keySyncTheme) ?? true,
      themeOverride: prefs.getString(_keyThemeOverride) ?? 'tokyo-night',
      cachedThemeJson: prefs.getString(_keyCachedTheme) ?? '',
      autoSyncClipboard: prefs.getBool(_keyAutoClip) ?? false,
      useTls: prefs.getBool(_keyUseTls) ?? false,
      tlsFingerprint: prefs.getString(_keyTlsFp) ?? '',
      tailscaleHost: prefs.getString(_keyTailscaleHost) ?? '',
      vitalsNotification: prefs.getBool(_keyVitalsNotif) ?? true,
      avatarStyle: prefs.getString(_keyAvatarStyle) ?? 'classic',
      launcherIcon: prefs.getString(_keyLauncherIcon) ?? 'classic',
    );
  }

  Future<void> save(WizardSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, settings.host);
    await prefs.setInt(_keyPort, settings.port);
    await prefs.setString(_keyToken, settings.token);
    await prefs.setBool(_keyDemo, settings.demoMode);
    await prefs.setBool(_keyNotify, settings.notifyOnComplete);
    await prefs.setString(_keyMode, settings.defaultMode);
    await prefs.setString(_keyEffort, settings.defaultEffort);
    await prefs.setBool(_keyRelayNotif, settings.relayNotifications);
    await prefs.setBool(_keyRelayCalls, settings.relayCalls);
    await prefs.setBool(_keySyncTheme, settings.syncOmarchyTheme);
    await prefs.setString(_keyThemeOverride, settings.themeOverride);
    await prefs.setString(_keyCachedTheme, settings.cachedThemeJson);
    await prefs.setBool(_keyAutoClip, settings.autoSyncClipboard);
    await prefs.setBool(_keyUseTls, settings.useTls);
    await prefs.setString(_keyTlsFp, settings.tlsFingerprint);
    await prefs.setString(_keyTailscaleHost, settings.tailscaleHost);
    await prefs.setBool(_keyVitalsNotif, settings.vitalsNotification);
    await prefs.setString(_keyAvatarStyle, settings.avatarStyle);
    await prefs.setString(_keyLauncherIcon, settings.launcherIcon);
  }
}
