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
  });

  final String host;
  final int port;
  final String token;
  final bool demoMode;
  final bool notifyOnComplete;
  final String defaultMode;
  final String defaultEffort;

  String get httpBaseUrl => 'http://$host:$port';
  String get wsUrl => 'ws://$host:$port/ws';
  String get terminalWsUrl => 'ws://$host:$port/ws/terminal';

  WizardSettings copyWith({
    String? host,
    int? port,
    String? token,
    bool? demoMode,
    bool? notifyOnComplete,
    String? defaultMode,
    String? defaultEffort,
  }) {
    return WizardSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      demoMode: demoMode ?? this.demoMode,
      notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
      defaultMode: defaultMode ?? this.defaultMode,
      defaultEffort: defaultEffort ?? this.defaultEffort,
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
  }
}
