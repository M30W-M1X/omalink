import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class ContinuitySharePayload {
  const ContinuitySharePayload({
    required this.text,
    this.subject = '',
    this.packageName = '',
  });

  final String text;
  final String subject;
  final String packageName;
}

class ContinuityService {
  ContinuityService._();
  static final ContinuityService instance = ContinuityService._();

  static const MethodChannel _method =
      MethodChannel('com.omarchy.wizard/continuity');
  static const EventChannel _events =
      EventChannel('com.omarchy.wizard/continuity_events');

  StreamSubscription<dynamic>? _sub;

  Future<bool> isNotificationListenerEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _method.invokeMethod<bool>('isNotificationListenerEnabled');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationListenerSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _method.invokeMethod<void>('openNotificationListenerSettings');
    } catch (_) {}
  }

  Future<ContinuitySharePayload?> consumePendingShare() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _method.invokeMapMethod<dynamic, dynamic>('consumePendingShare');
      if (raw == null) return null;
      final text = raw['text']?.toString() ?? '';
      if (text.isEmpty) return null;
      return ContinuitySharePayload(
        text: text,
        subject: raw['subject']?.toString() ?? '',
        packageName: raw['packageName']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  void startListening({
    required void Function(ContinuitySharePayload share) onShare,
    required void Function(Map<String, dynamic> relayed) onRelayedNotification,
  }) {
    if (!Platform.isAndroid || _sub != null) return;
    try {
      _sub = _events.receiveBroadcastStream().listen(
        (dynamic item) {
          if (item is! Map) return;
          final map = Map<String, dynamic>.from(item);
          final ev = map['event']?.toString();
          if (ev == 'share') {
            final text = map['text']?.toString() ?? '';
            if (text.isNotEmpty) {
              onShare(
                ContinuitySharePayload(
                  text: text,
                  subject: map['subject']?.toString() ?? '',
                  packageName: map['packageName']?.toString() ?? '',
                ),
              );
            }
          } else if (ev == 'relayed_notification') {
            onRelayedNotification(map);
          }
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
