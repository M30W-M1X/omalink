import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/agent_task.dart';
import '../models/system_control.dart';

class VitalsShadeContent {
  const VitalsShadeContent({
    required this.title,
    required this.body,
    required this.lines,
    required this.summaryText,
  });

  final String title;
  final String body;
  final List<String> lines;
  final String summaryText;
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'omalink_tasks';
  static const String _channelName = 'OmaLink Agent Alerts';
  static const String _channelDescription =
      'Notifications when your Omarchy AI agent completes or fails a task.';

  static const String _vitalsChannelId = 'omalink_vitals';
  static const String _vitalsChannelName = 'OmaLink Vitals & Agy Limits';
  static const String _vitalsChannelDescription =
      'Silent ongoing shade notification with live machine vitals and Antigravity usage limits.';
  static const int _vitalsNotificationId = 4243;

  static const String _smallIcon = 'ic_wizard_notify';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionPrompted = false;

  Future<void> init({bool requestPermissionIfNeeded = false}) async {
    if (!_initialized) {
      const androidInit = AndroidInitializationSettings(_smallIcon);
      const initSettings = InitializationSettings(android: androidInit);

      try {
        await _plugin.initialize(initSettings);
        final androidImpl = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDescription,
              importance: Importance.high,
              enableVibration: true,
              playSound: true,
            ),
          );
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              _vitalsChannelId,
              _vitalsChannelName,
              description: _vitalsChannelDescription,
              importance: Importance.low,
              enableVibration: false,
              playSound: false,
              showBadge: false,
            ),
          );
        }
        _initialized = true;
      } catch (e) {
        debugPrint('NotificationService init skipped: $e');
        return;
      }
    }

    if (requestPermissionIfNeeded && !_permissionPrompted) {
      _permissionPrompted = true;
      await ensurePermission();
    }
  }

  Future<bool> ensurePermission() async {
    await init();
    if (!_initialized) return false;
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) return false;
      final alreadyEnabled = await androidImpl.areNotificationsEnabled();
      if (alreadyEnabled == true) return true;
      final granted = await androidImpl.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Notification permission check failed: $e');
      return false;
    }
  }

  Future<bool> requestPermission() => ensurePermission();

  static String _formatUptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  static String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M tok';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(0)}K tok';
    return '$tokens tok';
  }

  static VitalsShadeContent formatVitalsNotification(
    SystemState state,
    List<AgentUsageInfo> usage, {
    int runningTasks = 0,
  }) {
    final cpu = state.cpuPercent.round();
    final ramUsed = state.memory.usedGb.toStringAsFixed(1);
    final ramTotal = state.memory.totalGb.toStringAsFixed(0);
    final ramPct = state.memory.percent.round();

    AgentUsageInfo? agy;
    for (final item in usage) {
      if (item.id.toLowerCase() == 'agy') {
        agy = item;
        break;
      }
    }
    agy ??= usage.isNotEmpty ? usage.first : null;

    final title = '${state.hostname} · CPU $cpu% · RAM $ramUsed/${ramTotal}G';

    String agyCompact = 'Agy usage loading...';
    final lines = <String>[
      'CPU $cpu% (load ${state.loadAvg}) · RAM $ramUsed/$ramTotal GB ($ramPct%)',
    ];

    if (state.battery.present) {
      lines.add(
        'Battery ${state.battery.percent}% (${state.battery.status}) · Up ${_formatUptime(state.uptimeSeconds)}',
      );
    } else {
      final themeName = state.theme.current.isNotEmpty ? ' · ${state.theme.current}' : '';
      lines.add('Uptime ${_formatUptime(state.uptimeSeconds)}$themeName');
    }

    if (agy != null) {
      final tier = agy.tierLabel.isNotEmpty ? ' (${agy.tierLabel})' : '';
      final limitParts = agy.limits
          .take(3)
          .map((l) => '${l.title} ${l.percent.round()}%')
          .toList();
      agyCompact = limitParts.isNotEmpty
          ? 'Agy: ${limitParts.join(' · ')} (${agy.todayPrompts} today)'
          : 'Agy$tier: ${agy.todayPrompts} prompts today';

      final tokPart = agy.todayTokens > 0 ? ' · ${_formatTokens(agy.todayTokens)}' : '';
      lines.add('Agy$tier: ${agy.todayPrompts} prompts today$tokPart');
      if (limitParts.isNotEmpty) {
        lines.add('Limits used: ${limitParts.join(' · ')}');
      }
    }

    if (runningTasks > 0) {
      lines.add('Active spells: $runningTasks running');
    } else if (state.audio.player.available && state.audio.player.title.isNotEmpty) {
      lines.add('♫ ${state.audio.player.title} — ${state.audio.player.artist}');
    }

    return VitalsShadeContent(
      title: title,
      body: agyCompact,
      lines: lines,
      summaryText: 'Omarchy ${state.osVersion}',
    );
  }

  Future<void> showVitalsNotification(
    SystemState state,
    List<AgentUsageInfo> usage, {
    int runningTasks = 0,
  }) async {
    await init();
    if (!_initialized) return;

    final content = formatVitalsNotification(
      state,
      usage,
      runningTasks: runningTasks,
    );

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _vitalsChannelId,
        _vitalsChannelName,
        channelDescription: _vitalsChannelDescription,
        importance: Importance.low,
        priority: Priority.low,
        icon: _smallIcon,
        silent: true,
        playSound: false,
        enableVibration: false,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: true,
        styleInformation: InboxStyleInformation(
          content.lines,
          contentTitle: content.title,
          summaryText: content.summaryText,
        ),
      ),
    );

    try {
      await _plugin.show(
        _vitalsNotificationId,
        content.title,
        content.body,
        details,
      );
    } catch (e) {
      debugPrint('Failed to update vitals shade notification: $e');
    }
  }

  Future<void> cancelVitalsNotification() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_vitalsNotificationId);
    } catch (_) {}
  }

  Future<void> notifyTaskFinished(AgentTask task) async {
    await init(requestPermissionIfNeeded: true);
    if (!_initialized) return;

    final succeeded = task.status == TaskStatus.completed;
    final emoji = succeeded ? '✨' : '💥';
    final verb = succeeded ? 'Spell Complete' : 'Spell Fizzled';
    final duration = task.durationSeconds != null
        ? ' (${task.durationSeconds!.toStringAsFixed(1)}s)'
        : '';
    final title = '$emoji $verb via ${task.agent}$duration';
    final body = task.summary.isNotEmpty ? task.summary : task.prompt;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: _smallIcon,
        styleInformation: BigTextStyleInformation(body),
      ),
    );

    try {
      await _plugin.show(
        task.id.hashCode & 0x7FFFFFFF,
        title,
        body,
        details,
      );
    } catch (e) {
      debugPrint('Failed to display notification: $e');
    }
  }

  Future<String?> showTestNotification() async {
    await init();
    if (!_initialized) {
      return 'Notification plugin could not initialize.';
    }

    final permitted = await ensurePermission();
    if (!permitted) {
      return 'Notifications are blocked by Android. Grant permission in system settings.';
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: _smallIcon,
      ),
    );

    try {
      await _plugin.show(
        4242,
        '✨ Arcane Agy is ready!',
        'Task completion notifications from Omarchy will appear right here.',
        details,
      );
      return null;
    } catch (e) {
      debugPrint('Test notification failed: $e');
      return 'Failed to show alert: $e';
    }
  }
}
