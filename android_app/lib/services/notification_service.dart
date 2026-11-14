import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/agent_task.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'omarchy_wizard_tasks';
  static const String _channelName = 'Wizard Spell Completions';
  static const String _channelDescription =
      'Notifications when your Omarchy AI agent completes or fails a task.';
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
