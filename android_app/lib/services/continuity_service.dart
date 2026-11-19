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

class ContinuityFileSharePayload {
  const ContinuityFileSharePayload({
    required this.filename,
    required this.dataBase64,
    this.mimeType = '',
    this.packageName = '',
  });

  final String filename;
  final String dataBase64;
  final String mimeType;
  final String packageName;
}

class DiscoveredBridge {
  const DiscoveredBridge({
    required this.name,
    required this.host,
    required this.port,
    this.tls = false,
    this.fingerprint = '',
    this.tailscaleIp = '',
  });

  final String name;
  final String host;
  final int port;
  final bool tls;
  final String fingerprint;
  final String tailscaleIp;
}

class PhoneDeviceStatus {
  const PhoneDeviceStatus({
    required this.name,
    required this.battery,
    required this.charging,
  });

  final String name;
  final int battery;
  final bool charging;
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

  Future<Map<String, dynamic>?> consumePendingShareRaw() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _method.invokeMapMethod<dynamic, dynamic>('consumePendingShare');
      if (raw == null) return null;
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  Future<String?> consumePendingPairUri() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _method.invokeMethod<String>('consumePendingPairUri');
      return (raw != null && raw.isNotEmpty) ? raw : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> replyToNotification(String replyId, String text) async {
    if (!Platform.isAndroid || replyId.isEmpty || text.isEmpty) return false;
    try {
      final ok = await _method.invokeMethod<bool>('replyToNotification', {
        'replyId': replyId,
        'text': text,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<PhoneDeviceStatus?> getDeviceStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _method.invokeMapMethod<dynamic, dynamic>('getDeviceStatus');
      if (raw == null) return null;
      return PhoneDeviceStatus(
        name: raw['name']?.toString() ?? 'Android',
        battery: (raw['battery'] as num?)?.toInt() ?? -1,
        charging: raw['charging'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> ringPhone({int duration = 12}) async {
    if (!Platform.isAndroid) return;
    try {
      await _method.invokeMethod<void>('ringPhone', {'duration': duration});
    } catch (_) {}
  }

  Future<void> stopRinging() async {
    if (!Platform.isAndroid) return;
    try {
      await _method.invokeMethod<void>('stopRinging');
    } catch (_) {}
  }

  Future<List<DiscoveredBridge>> discoverBridges() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _method.invokeListMethod<dynamic>('discoverBridges');
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (m) => DiscoveredBridge(
              name: m['name']?.toString() ?? 'Omarchy Wizard',
              host: m['host']?.toString() ?? '',
              port: (m['port'] as num?)?.toInt() ?? 7842,
              tls: m['tls'] == true,
              fingerprint: m['fp']?.toString() ?? '',
              tailscaleIp: m['ts']?.toString() ?? '',
            ),
          )
          .where((b) => b.host.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String?> saveToDownloads(String filename, Uint8List bytes) async {
    if (!Platform.isAndroid) return 'Downloads/$filename';
    try {
      return await _method.invokeMethod<String>('saveToDownloads', {
        'filename': filename,
        'bytes': bytes,
      });
    } catch (_) {
      return null;
    }
  }

  Future<bool> setLauncherIcon(String iconId) async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _method.invokeMethod<bool>('setLauncherIcon', {
        'iconId': iconId,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> getLauncherIcon() async {
    if (!Platform.isAndroid) return 'classic';
    try {
      final id = await _method.invokeMethod<String>('getLauncherIcon');
      return (id != null && id.isNotEmpty) ? id : 'classic';
    } catch (_) {
      return 'classic';
    }
  }

  void startListening({
    required void Function(ContinuitySharePayload share) onShare,
    required void Function(ContinuityFileSharePayload fileShare) onFileShare,
    required void Function(String pairUri) onPairUri,
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
          } else if (ev == 'share_file') {
            final b64 = map['dataBase64']?.toString() ?? '';
            if (b64.isNotEmpty) {
              onFileShare(
                ContinuityFileSharePayload(
                  filename: map['filename']?.toString() ?? 'shared_file',
                  dataBase64: b64,
                  mimeType: map['mimeType']?.toString() ?? '',
                  packageName: map['packageName']?.toString() ?? '',
                ),
              );
            }
          } else if (ev == 'pair_uri') {
            final uri = map['uri']?.toString() ?? '';
            if (uri.isNotEmpty) onPairUri(uri);
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
