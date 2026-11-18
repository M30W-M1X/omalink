import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/agent_task.dart';
import '../models/system_control.dart';
import '../models/wizard_mood.dart';
import '../theme/wizard_theme.dart';
import 'continuity_service.dart';
import 'notification_service.dart';
import 'settings_store.dart';
import 'tls_overrides.dart';

enum BridgeConnectionState {
  disconnected,
  connecting,
  connected,
  demo,
}

class BridgeClient extends ChangeNotifier {
  BridgeClient({
    SettingsStore? settingsStore,
    NotificationService? notifications,
  })  : _settingsStore = settingsStore ?? SettingsStore(),
        _notifications = notifications ?? NotificationService.instance;

  final SettingsStore _settingsStore;
  final NotificationService _notifications;

  WizardSettings _settings = const WizardSettings();
  WizardSettings get settings => _settings;

  BridgeConnectionState _connectionState = BridgeConnectionState.demo;
  BridgeConnectionState get connectionState => _connectionState;

  HostStatus _hostStatus = HostStatus.demo();
  HostStatus get hostStatus => _hostStatus;

  final List<AgentTask> _tasks = <AgentTask>[];
  List<AgentTask> get tasks => List.unmodifiable(_tasks);

  String? _selectedTaskId;
  AgentTask? get activeOrSelectedTask {
    if (_selectedTaskId != null) {
      for (final t in _tasks) {
        if (t.id == _selectedTaskId) return t;
      }
    }
    return _tasks.isNotEmpty ? _tasks.first : null;
  }

  String _selectedAgent = 'agy';
  String get selectedAgent => _selectedAgent;

  String _selectedMode = 'auto';
  String get selectedMode => _selectedMode;

  String _selectedEffort = 'high';
  String get selectedEffort => _selectedEffort;

  String _selectedWorkspace = '~/Work';
  String get selectedWorkspace => _selectedWorkspace;

  String? _lastError;
  String? get lastError => _lastError;

  WizardMood _mood = WizardMood.idle;
  WizardMood get mood => _mood;

  String _wizardQuip = WizardMood.idle.defaultQuip;
  String get wizardQuip => _wizardQuip;

  SystemState _systemState = SystemState.demo();
  SystemState get systemState => _systemState;

  bool _systemLoading = false;
  bool get systemLoading => _systemLoading;

  String? _systemMessage;
  String? get systemMessage => _systemMessage;

  DirectoryListing? _currentDirectory;
  DirectoryListing? get currentDirectory => _currentDirectory;

  bool _filesLoading = false;
  bool get filesLoading => _filesLoading;

  bool _showHiddenFiles = false;
  bool get showHiddenFiles => _showHiddenFiles;

  String? _filesError;
  String? get filesError => _filesError;

  String? _pendingPromptDraft;
  String? consumePendingPromptDraft() {
    final draft = _pendingPromptDraft;
    _pendingPromptDraft = null;
    return draft;
  }

  void stageAgentInDirectory(String dirPath, {String? filePath}) {
    _selectedWorkspace = dirPath;
    if (filePath != null && filePath.isNotEmpty) {
      _pendingPromptDraft = 'Inspect $filePath';
    }
    notifyListeners();
  }

  String? _pendingTerminalCwd;
  String? consumePendingTerminalCwd() {
    final cwd = _pendingTerminalCwd;
    _pendingTerminalCwd = null;
    return cwd;
  }

  void stageTerminalInDirectory(String dirPath) {
    _pendingTerminalCwd = dirPath;
    notifyListeners();
  }

  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  Timer? _celebrateResetTimer;
  Timer? _demoTimer;
  Timer? _batteryTimer;
  final Set<String> _watchedTaskIds = <String>{};

  bool _isRinging = false;
  bool get isRinging => _isRinging;

  List<String> _desktopClipboardHistory = const [];
  List<String> get desktopClipboardHistory => List.unmodifiable(_desktopClipboardHistory);

  List<AgentUsageInfo> _agentUsage = const [];
  List<AgentUsageInfo> get agentUsage => List.unmodifiable(_agentUsage);

  String _detectedTailscaleIp = '';
  String get detectedTailscaleIp =>
      _detectedTailscaleIp.isNotEmpty ? _detectedTailscaleIp : _settings.tailscaleHost;

  void _configureTlsOverrides() {
    if (_settings.useTls && !_settings.demoMode && _settings.host.isNotEmpty) {
      HttpOverrides.global = WizardTlsOverrides(
        allowedHost: _settings.host,
        pinnedSha256: _settings.tlsFingerprint,
      );
    } else {
      HttpOverrides.global = null;
    }
  }
  final Set<String> _notifiedTaskIds = <String>{};
  bool _disposed = false;

  bool _notificationAccessEnabled = false;
  bool get notificationAccessEnabled => _notificationAccessEnabled;

  String _desktopClipboardPreview = '';
  String get desktopClipboardPreview => _desktopClipboardPreview;

  List<Map<String, dynamic>> _continuityApps = const [
    {'id': 'browser', 'label': 'Chrome / Browser', 'available': true},
    {'id': 'spotify', 'label': 'Spotify', 'available': true},
    {'id': 'terminal', 'label': 'Terminal', 'available': true},
    {'id': 'files', 'label': 'Files', 'available': true},
  ];
  List<Map<String, dynamic>> get continuityApps => List.unmodifiable(_continuityApps);

  final List<Map<String, dynamic>> _continuityActivity = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> get continuityActivity => List.unmodifiable(_continuityActivity);

  String? _continuityBanner;
  String? get continuityBanner => _continuityBanner;

  WizardPalette _desktopPalette = WizardPalette.tokyoNight;
  WizardPalette get desktopPalette => _desktopPalette;
  WizardPalette get activePalette => _settings.syncOmarchyTheme
      ? _desktopPalette
      : WizardPalette.byName(_settings.themeOverride);

  void _syncActiveColors() {
    WizardColors.apply(activePalette);
  }

  void _applyDesktopThemeJson(Map<String, dynamic> themeJson, {bool persist = true}) {
    final parsed = WizardPalette.fromOmarchyJson(themeJson);
    _desktopPalette = parsed;
    _syncActiveColors();
    if (persist && !_settings.demoMode) {
      final encoded = jsonEncode(parsed.toOmarchyJson());
      if (encoded != _settings.cachedThemeJson) {
        _settings = _settings.copyWith(cachedThemeJson: encoded);
        unawaited(_settingsStore.save(_settings));
      }
    }
    notifyListeners();
  }

  Future<void> updateThemePreferences({
    bool? syncOmarchyTheme,
    String? themeOverride,
  }) async {
    _settings = _settings.copyWith(
      syncOmarchyTheme: syncOmarchyTheme,
      themeOverride: themeOverride,
    );
    _syncActiveColors();
    await _settingsStore.save(_settings);
    notifyListeners();
    if (_settings.syncOmarchyTheme && !_settings.demoMode) {
      unawaited(refreshDesktopTheme());
    }
  }

  Future<void> refreshDesktopTheme() async {
    if (_settings.demoMode) return;
    try {
      final resp = await http
          .get(
            Uri.parse('${_settings.httpBaseUrl}/api/theme/current'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        _applyDesktopThemeJson(decoded);
      }
    } catch (_) {}
  }

  Future<void> init() async {
    _settings = await _settingsStore.load();
    _selectedMode = _settings.defaultMode;
    _selectedEffort = _settings.defaultEffort;
    if (_settings.cachedThemeJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(_settings.cachedThemeJson);
        if (decoded is Map<String, dynamic>) {
          _desktopPalette = WizardPalette.fromOmarchyJson(decoded);
        }
      } catch (_) {}
    }
    _syncActiveColors();
    _configureTlsOverrides();

    _notificationAccessEnabled =
        await ContinuityService.instance.isNotificationListenerEnabled();
    ContinuityService.instance.startListening(
      onShare: (share) {
        unawaited(
          handoffToOmarchy(
            text: share.text,
            subject: share.subject,
            packageName: share.packageName,
          ),
        );
      },
      onFileShare: (fileShare) {
        unawaited(uploadSharedFile(fileShare.filename, fileShare.dataBase64));
      },
      onPairUri: (pairUri) {
        unawaited(applyPairingUri(pairUri));
      },
      onRelayedNotification: (relayed) {
        _continuityActivity.insert(0, {
          ...relayed,
          'ts': DateTime.now().toIso8601String(),
        });
        if (_continuityActivity.length > 25) {
          _continuityActivity.removeLast();
        }
        notifyListeners();
      },
    );

    if (_settings.demoMode) {
      _activateDemoMode();
    } else {
      await connect();
    }

    final initialPairUri = await ContinuityService.instance.consumePendingPairUri();
    if (initialPairUri != null) {
      unawaited(applyPairingUri(initialPairUri));
    }

    final initialShareRaw = await ContinuityService.instance.consumePendingShareRaw();
    if (initialShareRaw != null) {
      final ev = initialShareRaw['event']?.toString() ?? 'share';
      if (ev == 'share_file') {
        final b64 = initialShareRaw['dataBase64']?.toString() ?? '';
        if (b64.isNotEmpty) {
          unawaited(
            uploadSharedFile(
              initialShareRaw['filename']?.toString() ?? 'shared_file',
              b64,
            ),
          );
        }
      } else {
        final txt = initialShareRaw['text']?.toString() ?? '';
        if (txt.isNotEmpty) {
          unawaited(
            handoffToOmarchy(
              text: txt,
              subject: initialShareRaw['subject']?.toString() ?? '',
              packageName: initialShareRaw['packageName']?.toString() ?? '',
            ),
          );
        }
      }
    }
  }

  void setSelectedAgent(String agent) {
    _selectedAgent = agent;
    notifyListeners();
  }

  void setSelectedMode(String mode) {
    _selectedMode = mode;
    notifyListeners();
  }

  void setSelectedEffort(String effort) {
    _selectedEffort = effort;
    notifyListeners();
  }

  void setSelectedWorkspace(String workspace) {
    _selectedWorkspace = workspace;
    notifyListeners();
  }

  void selectTask(String taskId) {
    _selectedTaskId = taskId;
    notifyListeners();
    if (!_settings.demoMode) {
      unawaited(refreshTaskDetails(taskId));
    }
  }

  void setListeningMood(bool listening) {
    if (_hasRunningTask) return;
    _setMood(listening ? WizardMood.listening : WizardMood.idle);
  }

  void triggerWizardBoop() {
    const boops = [
      'Boop! +10 Arcane Mana ✨',
      'Arcane Agy loves tidy diffs!',
      'Ready to cast spells on Omarchy!',
      'May your builds stay forever green 🌟',
      'Hyprland windows aligned, Master Wizard!',
    ];
    final nextQuip = boops[DateTime.now().millisecond % boops.length];
    _wizardQuip = nextQuip;
    if (!_hasRunningTask) {
      _mood = WizardMood.celebrating;
      _celebrateResetTimer?.cancel();
      _celebrateResetTimer = Timer(const Duration(seconds: 2), () {
        if (!_hasRunningTask && !_disposed) {
          _setMood(WizardMood.idle);
        }
      });
    }
    notifyListeners();
  }

  bool get _hasRunningTask => _tasks.any((t) => t.status == TaskStatus.running);

  void _setMood(WizardMood next, {String? quip}) {
    _mood = next;
    _wizardQuip = quip ?? next.defaultQuip;
    notifyListeners();
  }

  Future<void> updateSettings(WizardSettings next) async {
    _settings = next;
    _syncActiveColors();
    _configureTlsOverrides();
    await _settingsStore.save(next);
    _lastError = null;
    if (next.demoMode) {
      await _disconnectSocket();
      _activateDemoMode();
    } else {
      await connect();
    }
  }

  Future<void> updateRelayPreferences({
    bool? relayNotifications,
    bool? relayCalls,
  }) async {
    _settings = _settings.copyWith(
      relayNotifications: relayNotifications,
      relayCalls: relayCalls,
    );
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  void _activateDemoMode() {
    _connectionState = BridgeConnectionState.demo;
    _hostStatus = HostStatus.demo();
    _systemState = SystemState.demo();
    _currentDirectory = DirectoryListing.demo();
    if (!_hostStatus.availableAgents.contains(_selectedAgent)) {
      _selectedAgent = _hostStatus.defaultAgent;
    }
    if (!_hostStatus.workspaces.contains(_selectedWorkspace)) {
      _selectedWorkspace = _hostStatus.workspaces.first;
    }
    _lastError = null;
    unawaited(refreshAgentUsage());
    _setMood(_hasRunningTask ? WizardMood.casting : WizardMood.idle);
  }

  Future<void> connect() async {
    if (_settings.demoMode) {
      _activateDemoMode();
      return;
    }
    _reconnectTimer?.cancel();
    await _disconnectSocket();
    _connectionState = BridgeConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final uri = Uri.parse(_settings.wsUrl).replace(
        queryParameters: {'token': _settings.token},
      );
      _ws = await WebSocket.connect(
        uri.toString(),
        headers: {'Authorization': 'Bearer ${_settings.token}'},
      ).timeout(const Duration(seconds: 6));

      _connectionState = BridgeConnectionState.connected;
      _wsSub = _ws!.listen(
        _handleWsMessage,
        onError: (Object err) {
          _lastError = 'Stream error: $err';
          _scheduleReconnect();
        },
        onDone: () {
          if (!_settings.demoMode && !_disposed) {
            _scheduleReconnect();
          }
        },
        cancelOnError: true,
      );
      notifyListeners();
      unawaited(refreshSystemState());
      unawaited(browseDirectory());
    } catch (err) {
      _connectionState = BridgeConnectionState.disconnected;
      _lastError = 'Could not reach Omarchy bridge (${_settings.host}:${_settings.port}): $err';
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _settings.demoMode) return;
    _connectionState = BridgeConnectionState.disconnected;
    notifyListeners();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed && !_settings.demoMode) {
        unawaited(connect());
      }
    });
  }

  Future<void> _disconnectSocket() async {
    await _wsSub?.cancel();
    _wsSub = null;
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  void _handleWsMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final type = decoded['type']?.toString() ?? '';
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return;

      switch (type) {
        case 'hello':
          if (data['status'] is Map<String, dynamic>) {
            final statusMap = data['status'] as Map<String, dynamic>;
            _applyHostStatus(HostStatus.fromJson(statusMap));
            if (statusMap['theme'] is Map<String, dynamic>) {
              _applyDesktopThemeJson(statusMap['theme'] as Map<String, dynamic>);
            }
            final tsIp = statusMap['tailscale_ip']?.toString() ?? '';
            if (tsIp.isNotEmpty) {
              _detectedTailscaleIp = tsIp;
            }
          }
          unawaited(_reportDeviceBattery());
          _startBatteryHeartbeat();
          unawaited(refreshAgentUsage());
          if (data['tasks'] is List) {
            _tasks
              ..clear()
              ..addAll(
                (data['tasks'] as List)
                    .whereType<Map<String, dynamic>>()
                    .map(AgentTask.fromJson),
              );
            for (final t in _tasks) {
              if (t.status == TaskStatus.running) {
                _watchedTaskIds.add(t.id);
              } else if (_watchedTaskIds.remove(t.id) &&
                  (t.status == TaskStatus.completed ||
                      t.status == TaskStatus.failed)) {
                _onTaskTerminal(
                  t,
                  success: t.status == TaskStatus.completed,
                );
              }
            }
          }
          _syncMoodFromTasks();
          break;
        case 'task.started':
          final task = AgentTask.fromJson(data);
          _watchedTaskIds.add(task.id);
          _upsertTask(task);
          _selectedTaskId = task.id;
          _setMood(WizardMood.casting, quip: 'Casting "${task.prompt}"...');
          break;
        case 'task.event':
          final taskId = data['task_id']?.toString();
          final evJson = data['event'];
          if (taskId != null && evJson is Map<String, dynamic>) {
            _appendTaskEvent(
              taskId,
              TaskEvent.fromJson(evJson),
              conversationId: data['conversation_id']?.toString(),
            );
          }
          break;
        case 'task.completed':
          final task = AgentTask.fromJson(data);
          _upsertTask(task);
          _onTaskTerminal(task, success: true);
          break;
        case 'task.failed':
          final task = AgentTask.fromJson(data);
          _upsertTask(task);
          _onTaskTerminal(task, success: false);
          break;
        case 'task.cancelled':
          final task = AgentTask.fromJson(data);
          _upsertTask(task);
          _syncMoodFromTasks();
          break;
        case 'agent.default_changed':
          final nextDefault = data['default_agent']?.toString();
          if (nextDefault != null) {
            _hostStatus = HostStatus(
              hostname: _hostStatus.hostname,
              osName: _hostStatus.osName,
              osVersion: _hostStatus.osVersion,
              defaultAgent: nextDefault,
              availableAgents: _hostStatus.availableAgents,
              workspaces: _hostStatus.workspaces,
              runningTasks: _hostStatus.runningTasks,
            );
            notifyListeners();
          }
          break;
        case 'theme.changed':
          _applyDesktopThemeJson(data);
          break;
        case 'continuity.clipboard_update':
          final txt = data['text']?.toString() ?? '';
          final rawHist = data['history'] as List<dynamic>?;
          if (rawHist != null) {
            _desktopClipboardHistory = rawHist.map((e) => e.toString()).toList();
          }
          if (txt.isNotEmpty) {
            _desktopClipboardPreview = txt;
            if (_settings.autoSyncClipboard) {
              unawaited(Clipboard.setData(ClipboardData(text: txt)));
              _continuityBanner = 'Auto-synced desktop clipboard to phone';
            }
          }
          notifyListeners();
          break;
        case 'phone.reply':
          final replyId = data['reply_id']?.toString() ?? '';
          final replyText = data['text']?.toString() ?? '';
          if (replyId.isNotEmpty && replyText.isNotEmpty) {
            unawaited(
              ContinuityService.instance.replyToNotification(replyId, replyText),
            );
            _recordContinuityActivity('message', 'Inline Reply Sent', replyText);
          }
          break;
        case 'phone.ring':
          final duration = (data['duration'] as num?)?.toInt() ?? 12;
          _isRinging = true;
          notifyListeners();
          unawaited(ContinuityService.instance.ringPhone(duration: duration));
          Timer(Duration(seconds: duration), () {
            if (!_disposed && _isRinging) {
              _isRinging = false;
              notifyListeners();
            }
          });
          break;
      }
    } catch (e) {
      debugPrint('WS parse error: $e');
    }
  }

  void _applyHostStatus(HostStatus status) {
    _hostStatus = status;
    if (!status.availableAgents.contains(_selectedAgent)) {
      _selectedAgent = status.defaultAgent;
    }
    if (status.workspaces.isNotEmpty &&
        !status.workspaces.contains(_selectedWorkspace)) {
      _selectedWorkspace = status.workspaces.first;
    }
    notifyListeners();
  }

  void _upsertTask(AgentTask task) {
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx == -1) {
      _tasks.insert(0, task);
    } else {
      final existingEvents = _tasks[idx].events;
      _tasks[idx] = task.events.isEmpty
          ? task.copyWith(events: existingEvents)
          : task;
    }
    notifyListeners();
  }

  void _appendTaskEvent(
    String taskId,
    TaskEvent event, {
    String? conversationId,
  }) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final current = _tasks[idx];
    final updatedEvents = List<TaskEvent>.from(current.events)..add(event);
    _tasks[idx] = current.copyWith(
      events: updatedEvents,
      conversationId: conversationId ?? current.conversationId,
      summary: event.text.isNotEmpty ? event.text : current.summary,
    );
    if (event.kind.contains('plan') || _selectedMode == 'plan') {
      _mood = WizardMood.awaitingApproval;
    }
    notifyListeners();
  }

  void _onTaskTerminal(AgentTask task, {required bool success}) {
    _watchedTaskIds.remove(task.id);
    final isFirstAlert = _notifiedTaskIds.add(task.id);
    if (_settings.notifyOnComplete && isFirstAlert) {
      unawaited(_notifications.notifyTaskFinished(task));
    }
    _celebrateResetTimer?.cancel();
    _setMood(
      success ? WizardMood.celebrating : WizardMood.error,
      quip: success
          ? 'Spell complete! ${task.summary}'
          : 'Spell fizzled: ${task.summary}',
    );
    _celebrateResetTimer = Timer(const Duration(seconds: 4), () {
      if (!_disposed && !_hasRunningTask) {
        _setMood(WizardMood.idle);
      }
    });
  }

  void _syncMoodFromTasks() {
    if (_hasRunningTask) {
      _setMood(WizardMood.casting);
    } else {
      _setMood(WizardMood.idle);
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_settings.token}',
      };

  Future<void> castSpell(
    String prompt, {
    String? conversationId,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return;

    if (_settings.demoMode) {
      _runDemoSpell(cleanPrompt, conversationId: conversationId);
      return;
    }

    _lastError = null;
    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/tasks'),
            headers: _headers,
            body: jsonEncode({
              'prompt': cleanPrompt,
              'agent': _selectedAgent,
              'mode': _selectedMode,
              'effort': _selectedEffort,
              'cwd': _selectedWorkspace,
              if (conversationId != null) 'conversation_id': conversationId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 400) {
        _lastError = 'Bridge rejected spell (${resp.statusCode}): ${resp.body}';
        _setMood(WizardMood.error, quip: _lastError);
        return;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['task'] is Map<String, dynamic>) {
        final task = AgentTask.fromJson(body['task'] as Map<String, dynamic>);
        _watchedTaskIds.add(task.id);
        _upsertTask(task);
        _selectedTaskId = task.id;
        _setMood(WizardMood.casting, quip: 'Casting via $_selectedAgent...');
      }
    } catch (err) {
      _lastError = 'Failed to reach Omarchy bridge: $err';
      _setMood(WizardMood.error, quip: _lastError);
    }
  }

  Future<void> cancelActiveSpell(String taskId) async {
    if (_settings.demoMode) {
      _demoTimer?.cancel();
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        _tasks[idx] = _tasks[idx].copyWith(
          status: TaskStatus.cancelled,
          finishedAt: DateTime.now(),
          summary: 'Spell cancelled by Archmage.',
        );
      }
      _setMood(WizardMood.idle, quip: 'Spell dispelled cleanly.');
      return;
    }

    try {
      await http.post(
        Uri.parse('${_settings.httpBaseUrl}/api/tasks/$taskId/cancel'),
        headers: _headers,
      );
    } catch (err) {
      _lastError = 'Failed to cancel spell: $err';
      notifyListeners();
    }
  }

  Future<void> refreshTaskDetails(String taskId) async {
    if (_settings.demoMode) return;
    try {
      final resp = await http.get(
        Uri.parse('${_settings.httpBaseUrl}/api/tasks/$taskId'),
        headers: _headers,
      );
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        if (decoded['task'] is Map<String, dynamic>) {
          _upsertTask(AgentTask.fromJson(decoded['task'] as Map<String, dynamic>));
        }
      }
    } catch (_) {}
  }

  Future<void> setDefaultOmarchyAgent(String agent) async {
    _selectedAgent = agent;
    if (_settings.demoMode) {
      _hostStatus = HostStatus(
        hostname: _hostStatus.hostname,
        osName: _hostStatus.osName,
        osVersion: _hostStatus.osVersion,
        defaultAgent: agent,
        availableAgents: _hostStatus.availableAgents,
        workspaces: _hostStatus.workspaces,
        runningTasks: _hostStatus.runningTasks,
      );
      notifyListeners();
      return;
    }

    try {
      await http.post(
        Uri.parse('${_settings.httpBaseUrl}/api/agent/default'),
        headers: _headers,
        body: jsonEncode({'agent': agent}),
      );
    } catch (err) {
      _lastError = 'Could not update default agent: $err';
      notifyListeners();
    }
  }

  Future<void> refreshSystemState() async {
    if (_settings.demoMode) {
      _systemState = SystemState.demo();
      notifyListeners();
      return;
    }
    _systemLoading = true;
    notifyListeners();
    try {
      final resp = await http
          .get(
            Uri.parse('${_settings.httpBaseUrl}/api/system/state'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        _systemState = SystemState.fromJson(decoded);
        if (_systemState.theme.palette != null) {
          _applyDesktopThemeJson(_systemState.theme.palette!);
        }
        _systemMessage = null;
      } else {
        _systemMessage = 'Telemetry error (${resp.statusCode})';
      }
    } catch (err) {
      _systemMessage = 'Failed to fetch OS state: $err';
    } finally {
      _systemLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendControlAction(
    String action, {
    Map<String, dynamic>? params,
  }) async {
    if (_settings.demoMode) {
      return _applyDemoControlAction(action, params ?? const {});
    }
    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/system/action'),
            headers: _headers,
            body: jsonEncode({
              'action': action,
              if (params != null && params.isNotEmpty) 'params': params,
            }),
          )
          .timeout(const Duration(seconds: 8));
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      _systemMessage = decoded['message']?.toString();
      if (decoded['state'] is Map<String, dynamic>) {
        _systemState = SystemState.fromJson(
          decoded['state'] as Map<String, dynamic>,
        );
        if (_systemState.theme.palette != null) {
          _applyDesktopThemeJson(_systemState.theme.palette!);
        }
      }
      if (decoded['ok'] == true) {
        _wizardQuip = _systemMessage ?? _wizardQuip;
      }
      notifyListeners();
      return decoded['ok'] == true;
    } catch (err) {
      _systemMessage = 'Control action failed: $err';
      notifyListeners();
      return false;
    }
  }

  bool _applyDemoControlAction(String action, Map<String, dynamic> params) {
    final s = _systemState;
    switch (action) {
      case 'audio.set_volume':
        final pct = ((params['percent'] as num?)?.toInt() ?? 50).clamp(0, 100);
        _systemState = s.copyWith(
          audio: s.audio.copyWith(volume: pct, muted: false),
        );
        _systemMessage = 'Demo volume set to $pct%';
        break;
      case 'audio.toggle_mute':
        _systemState = s.copyWith(
          audio: s.audio.copyWith(muted: !s.audio.muted),
        );
        _systemMessage = _systemState.audio.muted ? 'Audio muted (demo)' : 'Audio unmuted (demo)';
        break;
      case 'audio.toggle_mic_mute':
        _systemState = s.copyWith(
          audio: s.audio.copyWith(micMuted: !s.audio.micMuted),
        );
        _systemMessage = 'Microphone mute toggled (demo)';
        break;
      case 'audio.set_sink':
        final targetName = params['name']?.toString() ?? '';
        _systemState = s.copyWith(
          audio: s.audio.copyWith(
            defaultSink: targetName,
            sinks: s.audio.sinks
                .map((sink) => sink.copyWith(active: sink.name == targetName))
                .toList(),
          ),
        );
        _systemMessage = 'Switched audio output (demo)';
        break;
      case 'media.select_player':
        final bus = params['bus_name']?.toString() ?? '';
        for (final p in s.audio.players) {
          if (p.busName == bus) {
            _systemState = s.copyWith(audio: s.audio.copyWith(player: p));
            _systemMessage = 'Selected ${p.identity} (demo)';
            break;
          }
        }
        break;
      case 'media.play_pause':
        final nextStatus = s.audio.player.status == 'Playing' ? 'Paused' : 'Playing';
        _systemState = s.copyWith(
          audio: s.audio.copyWith(player: s.audio.player.copyWith(status: nextStatus)),
        );
        _systemMessage = '$nextStatus (demo)';
        break;
      case 'media.toggle_shuffle':
        final nextShuffle = !(s.audio.player.shuffle ?? false);
        _systemState = s.copyWith(
          audio: s.audio.copyWith(player: s.audio.player.copyWith(shuffle: nextShuffle)),
        );
        _systemMessage = 'Shuffle ${nextShuffle ? 'on' : 'off'} (demo)';
        break;
      case 'media.cycle_loop':
        const order = ['None', 'Playlist', 'Track'];
        final cur = s.audio.player.loopStatus ?? 'None';
        final nxt = order[(order.indexOf(cur) + 1) % order.length];
        _systemState = s.copyWith(
          audio: s.audio.copyWith(player: s.audio.player.copyWith(loopStatus: nxt)),
        );
        _systemMessage = 'Loop mode: $nxt (demo)';
        break;
      case 'toggle.nightlight':
        _systemState = s.copyWith(
          toggles: s.toggles.copyWith(nightlight: !s.toggles.nightlight),
        );
        _systemMessage = 'Toggled Nightlight (demo)';
        break;
      case 'toggle.idle':
        _systemState = s.copyWith(
          toggles: s.toggles.copyWith(stayAwake: !s.toggles.stayAwake),
        );
        _systemMessage = 'Toggled Stay Awake (demo)';
        break;
      case 'toggle.bar':
        _systemState = s.copyWith(
          toggles: s.toggles.copyWith(barHidden: !s.toggles.barHidden),
        );
        _systemMessage = 'Toggled Top Bar (demo)';
        break;
      case 'toggle.animations':
        _systemState = s.copyWith(
          toggles: s.toggles.copyWith(animationsOff: !s.toggles.animationsOff),
        );
        _systemMessage = 'Toggled Animations (demo)';
        break;
      case 'toggle.screensaver':
        _systemState = s.copyWith(
          toggles: s.toggles.copyWith(screensaverOff: !s.toggles.screensaverOff),
        );
        _systemMessage = 'Toggled Screensaver (demo)';
        break;
      case 'toggle.dnd':
        _systemState = s.copyWith(
          toggles: s.toggles.copyWith(dnd: !s.toggles.dnd),
        );
        _systemMessage = 'Toggled Do Not Disturb (demo)';
        break;
      case 'capture.screenrecord_toggle':
        _systemState = s.copyWith(
          capture: CaptureState(recording: !s.capture.recording),
        );
        _systemMessage = _systemState.capture.recording
            ? 'Started screen recording (demo)'
            : 'Stopped screen recording (demo)';
        break;
      case 'reminder.add':
        final mins = (params['minutes'] as num?)?.toInt() ?? 10;
        final msg = params['message']?.toString() ?? 'Reminder';
        final nextList = List<Map<String, dynamic>>.from(s.reminders.reminders)
          ..add({'message': msg, 'remaining': '${mins}m'});
        _systemState = s.copyWith(
          reminders: RemindersState(
            count: nextList.length,
            active: true,
            reminders: nextList,
          ),
        );
        _systemMessage = 'Set reminder for ${mins}m (demo)';
        break;
      case 'reminder.clear':
        _systemState = s.copyWith(reminders: const RemindersState());
        _systemMessage = 'Cleared reminders (demo)';
        break;
      case 'bluetooth.connect':
      case 'bluetooth.disconnect':
        final addr = params['address']?.toString() ?? '';
        final conn = action == 'bluetooth.connect';
        _systemState = s.copyWith(
          security: s.security.copyWith(
            bluetoothDevices: s.security.bluetoothDevices
                .map((d) => d.address == addr ? d.copyWith(connected: conn) : d)
                .toList(),
          ),
        );
        _systemMessage = '${conn ? 'Connected' : 'Disconnected'} Bluetooth device (demo)';
        break;
      case 'theme.set':
        final name = params['name']?.toString() ?? s.theme.current;
        _systemState = s.copyWith(theme: s.theme.copyWith(current: name));
        _desktopPalette = WizardPalette.byName(name);
        _syncActiveColors();
        _systemMessage = 'Demo theme set to $name';
        break;
      case 'hyprland.workspace':
        final wsId = (params['id'] as num?)?.toInt() ?? 1;
        _systemState = s.copyWith(
          hyprland: s.hyprland.copyWith(
            workspaces: s.hyprland.workspaces
                .map((w) => w.copyWith(active: w.id == wsId))
                .toList(),
          ),
        );
        _systemMessage = 'Switched to workspace $wsId (demo)';
        break;
      case 'security.sudo_disable':
        _systemState = s.copyWith(
          security: s.security.copyWith(passwordlessSudo: false),
        );
        _systemMessage = 'Passwordless sudo disabled (demo)';
        break;
      case 'security.sudo_prompt':
        _systemState = s.copyWith(
          security: s.security.copyWith(passwordlessSudo: true),
        );
        _systemMessage = 'Passwordless sudo enabled in demo mode';
        break;
      default:
        _systemMessage = 'Triggered $action (demo)';
    }
    notifyListeners();
    return true;
  }

  Future<void> browseDirectory([String? path, bool? showHidden]) async {
    if (showHidden != null) {
      _showHiddenFiles = showHidden;
    }
    if (_settings.demoMode) {
      _currentDirectory = DirectoryListing.demo(path);
      _filesError = null;
      notifyListeners();
      return;
    }
    _filesLoading = true;
    _filesError = null;
    notifyListeners();
    try {
      final uri = Uri.parse('${_settings.httpBaseUrl}/api/files/list').replace(
        queryParameters: {
          if (path != null && path.isNotEmpty) 'path': path,
          if (_showHiddenFiles) 'hidden': '1',
        },
      );
      final resp = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) {
        _currentDirectory = DirectoryListing.fromJson(decoded);
      } else {
        _filesError = decoded['error']?.toString() ?? 'Failed to open folder';
      }
    } catch (err) {
      _filesError = 'Failed to list files: $err';
    } finally {
      _filesLoading = false;
      notifyListeners();
    }
  }

  Future<FilePreview?> readFilePreview(String path) async {
    if (_settings.demoMode) {
      return FilePreview(
        path: path,
        name: path.split('/').last,
        size: 128,
        isBinary: false,
        truncated: false,
        content: '# Demo Scroll\n\nPreviewing $path in Demo Familiar Mode ✨\n',
      );
    }
    try {
      final uri = Uri.parse('${_settings.httpBaseUrl}/api/files/read').replace(
        queryParameters: {'path': path},
      );
      final resp = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        return FilePreview.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
      _filesError = 'Cannot read file (${resp.statusCode})';
      notifyListeners();
      return null;
    } catch (err) {
      _filesError = 'Failed to read file: $err';
      notifyListeners();
      return null;
    }
  }

  Future<bool> createFolder(String parentPath, String name) async {
    if (_settings.demoMode) {
      _currentDirectory = DirectoryListing.demo(parentPath);
      notifyListeners();
      return true;
    }
    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/files/mkdir'),
            headers: _headers,
            body: jsonEncode({'parent': parentPath, 'name': name}),
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode < 400) {
        await browseDirectory(parentPath);
        return true;
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      _filesError = decoded['error']?.toString() ?? 'Failed to create folder';
      notifyListeners();
      return false;
    } catch (err) {
      _filesError = 'Failed to create folder: $err';
      notifyListeners();
      return false;
    }
  }

  Future<bool> renameEntry(String targetPath, String newName) async {
    if (_settings.demoMode) return true;
    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/files/rename'),
            headers: _headers,
            body: jsonEncode({'path': targetPath, 'new_name': newName}),
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode < 400) {
        await browseDirectory(_currentDirectory?.path);
        return true;
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      _filesError = decoded['error']?.toString() ?? 'Rename failed';
      notifyListeners();
      return false;
    } catch (err) {
      _filesError = 'Rename failed: $err';
      notifyListeners();
      return false;
    }
  }

  Future<bool> openFileOnDesktop(String targetPath) async {
    if (_settings.demoMode) return true;
    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/files/open'),
            headers: _headers,
            body: jsonEncode({'path': targetPath}),
          )
          .timeout(const Duration(seconds: 6));
      return resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<bool> trashEntry(String targetPath) async {
    if (_settings.demoMode) return true;
    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/files/trash'),
            headers: _headers,
            body: jsonEncode({'path': targetPath}),
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode < 400) {
        await browseDirectory(_currentDirectory?.path);
        return true;
      }
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      _filesError = decoded['error']?.toString() ?? 'Failed to trash item';
      notifyListeners();
      return false;
    } catch (err) {
      _filesError = 'Failed to trash item: $err';
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshNotificationAccessStatus() async {
    _notificationAccessEnabled =
        await ContinuityService.instance.isNotificationListenerEnabled();
    notifyListeners();
  }

  Future<void> openNotificationAccessSettings() async {
    await ContinuityService.instance.openNotificationListenerSettings();
  }

  Future<void> refreshContinuityState() async {
    _notificationAccessEnabled =
        await ContinuityService.instance.isNotificationListenerEnabled();
    if (_settings.demoMode) {
      if (_desktopClipboardPreview.isEmpty) {
        _desktopClipboardPreview = 'https://wiki.archlinux.org/title/Hyprland';
      }
      if (_desktopClipboardHistory.isEmpty) {
        _desktopClipboardHistory = const [
          'https://wiki.archlinux.org/title/Hyprland',
          'systemctl --user status omarchy-wizard-bridge',
          'omarchy-theme-set nord',
        ];
      }
      notifyListeners();
      return;
    }
    try {
      final resp = await http
          .get(Uri.parse('${_settings.httpBaseUrl}/api/continuity/state'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final clip = data['clipboard'] as Map<String, dynamic>?;
        if (clip != null) {
          _desktopClipboardPreview = clip['text']?.toString() ?? '';
        }
        final rawHist = data['clipboard_history'] as List<dynamic>?;
        if (rawHist != null) {
          _desktopClipboardHistory = rawHist.map((e) => e.toString()).toList();
        }
        final apps = data['apps'] as List<dynamic>?;
        if (apps != null && apps.isNotEmpty) {
          _continuityApps = apps.cast<Map<String, dynamic>>();
        }
        final notifs = data['recent_notifications'] as List<dynamic>?;
        if (notifs != null && notifs.isNotEmpty && _continuityActivity.isEmpty) {
          _continuityActivity.addAll(notifs.cast<Map<String, dynamic>>());
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> stopRinging() async {
    _isRinging = false;
    notifyListeners();
    await ContinuityService.instance.stopRinging();
  }

  void _startBatteryHeartbeat() {
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_disposed && !_settings.demoMode) {
        unawaited(_reportDeviceBattery());
      }
    });
  }

  Future<void> _reportDeviceBattery() async {
    final status = await ContinuityService.instance.getDeviceStatus();
    if (status == null || status.battery < 0) return;
    final ws = _ws;
    if (ws != null && _connectionState == BridgeConnectionState.connected) {
      try {
        ws.add(jsonEncode({
          'type': 'device.status',
          'name': status.name,
          'battery': status.battery,
          'charging': status.charging,
        }));
      } catch (_) {}
    }
  }

  Future<bool> applyPairingUri(String rawUri) async {
    final parsed = Uri.tryParse(rawUri.trim());
    if (parsed == null || parsed.scheme != 'omarchy-wizard') return false;
    final host = parsed.queryParameters['host']?.trim() ?? '';
    final port = int.tryParse(parsed.queryParameters['port'] ?? '') ?? 7842;
    final token = parsed.queryParameters['token']?.trim() ?? '';
    final tls = parsed.queryParameters['tls'] == '1';
    final fp = parsed.queryParameters['fp']?.trim() ?? '';
    final ts = parsed.queryParameters['ts']?.trim() ?? '';
    if (host.isEmpty) return false;

    final next = _settings.copyWith(
      host: host,
      port: port,
      token: token,
      demoMode: false,
      useTls: tls,
      tlsFingerprint: fp,
      tailscaleHost: ts.isNotEmpty ? ts : _settings.tailscaleHost,
    );
    _continuityBanner = '✨ Paired with $host:$port${tls ? ' (TLS)' : ''}';
    await updateSettings(next);
    return true;
  }

  Future<List<DiscoveredBridge>> discoverLanBridges() async {
    return ContinuityService.instance.discoverBridges();
  }

  Future<bool> uploadSharedFile(String filename, String dataBase64, {String? destDir}) async {
    if (_settings.demoMode) {
      _continuityBanner = 'Uploaded $filename to ~/Downloads (demo)';
      _recordContinuityActivity('handoff', 'File Sent', filename);
      return true;
    }
    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/files/upload'),
            headers: _headers,
            body: jsonEncode({
              'filename': filename,
              'data_base64': dataBase64,
              if (destDir != null && destDir.isNotEmpty) 'dir': destDir,
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode < 400) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final saved = decoded['name']?.toString() ?? filename;
        _continuityBanner = '📥 Sent $saved to Omarchy!';
        _recordContinuityActivity('handoff', 'File Sent to PC', saved);
        return true;
      }
    } catch (_) {}
    _continuityBanner = 'Failed to upload $filename.';
    notifyListeners();
    return false;
  }

  Future<String?> downloadFileToPhone(String remotePath, String filename) async {
    if (_settings.demoMode) {
      return 'Downloads/$filename (demo)';
    }
    try {
      final uri = Uri.parse('${_settings.httpBaseUrl}/api/files/download')
          .replace(queryParameters: {'path': remotePath});
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final saved = await ContinuityService.instance.saveToDownloads(
          filename,
          resp.bodyBytes,
        );
        return saved;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> captureScreenshot() async {
    if (_settings.demoMode) {
      _systemMessage = 'Captured demo screenshot';
      notifyListeners();
      return {'ok': true, 'name': 'demo-screenshot.png', 'path': '~/Pictures/Screenshots/demo-screenshot.png'};
    }
    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/system/action'),
            headers: _headers,
            body: jsonEncode({'action': 'capture.screenshot'}),
          )
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      _systemMessage = decoded['message']?.toString();
      if (decoded['state'] is Map<String, dynamic>) {
        _systemState = SystemState.fromJson(decoded['state'] as Map<String, dynamic>);
      }
      notifyListeners();
      return decoded;
    } catch (err) {
      _systemMessage = 'Screenshot failed: $err';
      notifyListeners();
      return null;
    }
  }

  Future<void> refreshAgentUsage({bool force = false}) async {
    if (_settings.demoMode) {
      _agentUsage = const [
        AgentUsageInfo(
          id: 'agy',
          name: 'Antigravity',
          tierLabel: 'Pro',
          todayPrompts: 14,
          todayTokens: 1240000,
          limits: [
            AgentQuotaLimit(title: 'Session', percent: 18.0),
            AgentQuotaLimit(title: 'Weekly', percent: 32.0),
          ],
        ),
        AgentUsageInfo(
          id: 'claude',
          name: 'Claude',
          tierLabel: 'Max',
          todayPrompts: 6,
          todayTokens: 480000,
          limits: [AgentQuotaLimit(title: 'Session', percent: 12.0)],
        ),
      ];
      notifyListeners();
      return;
    }
    try {
      final uri = Uri.parse('${_settings.httpBaseUrl}/api/agents/usage')
          .replace(queryParameters: force ? {'force': '1'} : null);
      final resp = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final raw = decoded['agents'] as List<dynamic>? ?? const [];
        _agentUsage = raw
            .whereType<Map<String, dynamic>>()
            .map(AgentUsageInfo.fromJson)
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> updateAutoSyncClipboard(bool enabled) async {
    _settings = _settings.copyWith(autoSyncClipboard: enabled);
    await _settingsStore.save(_settings);
    notifyListeners();
  }

  Future<bool> sendClipboardToOmarchy({String? explicitText, bool notify = true}) async {
    var text = explicitText ?? '';
    if (text.isEmpty) {
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        text = data?.text ?? '';
      } catch (_) {}
    }
    if (text.trim().isEmpty) {
      _continuityBanner = 'Phone clipboard is empty.';
      notifyListeners();
      return false;
    }

    if (_settings.demoMode) {
      _desktopClipboardPreview = text;
      _continuityBanner = 'Synced clipboard to Omarchy (demo)';
      _recordContinuityActivity('clipboard', 'Clipboard Sent', text);
      return true;
    }

    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/continuity/clipboard'),
            headers: _headers,
            body: jsonEncode({'text': text, 'notify': notify}),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode < 400) {
        _desktopClipboardPreview = text;
        _continuityBanner = 'Clipboard synced to Omarchy!';
        _recordContinuityActivity('clipboard', 'Clipboard Sent', text);
        return true;
      }
    } catch (_) {}
    _continuityBanner = 'Failed to sync clipboard to Omarchy.';
    notifyListeners();
    return false;
  }

  Future<String?> pullClipboardFromOmarchy() async {
    if (_settings.demoMode) {
      final sample = _desktopClipboardPreview.isNotEmpty
          ? _desktopClipboardPreview
          : 'https://wiki.archlinux.org/title/Hyprland';
      try {
        await Clipboard.setData(ClipboardData(text: sample));
      } catch (_) {}
      _continuityBanner = 'Copied Omarchy clipboard to phone (demo)';
      _recordContinuityActivity('clipboard', 'Clipboard Pulled', sample);
      return sample;
    }

    try {
      final resp = await http
          .get(Uri.parse('${_settings.httpBaseUrl}/api/continuity/clipboard'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final text = data['text']?.toString() ?? '';
        _desktopClipboardPreview = text;
        if (text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
          _continuityBanner = 'Pulled Omarchy clipboard to phone!';
          _recordContinuityActivity('clipboard', 'Clipboard Pulled', text);
        } else {
          _continuityBanner = 'Omarchy clipboard is empty.';
          notifyListeners();
        }
        return text;
      }
    } catch (_) {}
    _continuityBanner = 'Failed to pull desktop clipboard.';
    notifyListeners();
    return null;
  }

  Future<bool> handoffToOmarchy({
    String url = '',
    String text = '',
    String subject = '',
    String app = '',
    String packageName = '',
  }) async {
    if (_settings.demoMode) {
      final target = url.isNotEmpty ? url : (app.isNotEmpty ? app : text);
      _continuityBanner = '✨ Continued on Omarchy (demo): $target';
      _recordContinuityActivity('handoff', 'Continue on Omarchy', target);
      return true;
    }

    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/continuity/handoff'),
            headers: _headers,
            body: jsonEncode({
              'url': url,
              'text': text,
              'subject': subject,
              'app': app,
              'package_name': packageName,
            }),
          )
          .timeout(const Duration(seconds: 6));
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode < 400 && decoded['ok'] == true) {
        _continuityBanner = decoded['message']?.toString() ?? 'Continued on Omarchy!';
        _recordContinuityActivity(
          'handoff',
          'Continue on Omarchy',
          _continuityBanner!,
        );
        return true;
      }
      _continuityBanner = decoded['error']?.toString() ?? decoded['message']?.toString() ?? 'Handoff failed.';
      notifyListeners();
      return false;
    } catch (err) {
      _continuityBanner = 'Handoff error: $err';
      notifyListeners();
      return false;
    }
  }

  Future<bool> relayNotificationToOmarchy({
    required String title,
    String body = '',
    String appName = 'Phone',
    String category = 'notification',
    String caller = '',
  }) async {
    if (_settings.demoMode) {
      _continuityBanner = 'Sent $category alert to Omarchy (demo)';
      _recordContinuityActivity(category, title, body);
      return true;
    }

    try {
      final resp = await http
          .post(
            Uri.parse('${_settings.httpBaseUrl}/api/continuity/notify'),
            headers: _headers,
            body: jsonEncode({
              'title': title,
              'body': body,
              'app_name': appName,
              'category': category,
              'caller': caller,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode < 400) {
        _continuityBanner = 'Delivered $category alert to Omarchy!';
        _recordContinuityActivity(category, title, body);
        return true;
      }
    } catch (_) {}
    _continuityBanner = 'Failed to deliver alert to Omarchy.';
    notifyListeners();
    return false;
  }

  void _recordContinuityActivity(String category, String title, String body) {
    _continuityActivity.insert(0, {
      'category': category,
      'title': title,
      'body': body,
      'ts': DateTime.now().toIso8601String(),
    });
    if (_continuityActivity.length > 25) {
      _continuityActivity.removeLast();
    }
    notifyListeners();
  }

  void _runDemoSpell(String prompt, {String? conversationId}) {
    _demoTimer?.cancel();
    final id = 'demo-${DateTime.now().millisecondsSinceEpoch}';
    final start = DateTime.now();
    final task = AgentTask(
      id: id,
      prompt: prompt,
      agent: _selectedAgent,
      mode: _selectedMode,
      effort: _selectedEffort,
      cwd: _selectedWorkspace,
      status: TaskStatus.running,
      createdAt: start,
      conversationId: conversationId ?? 'conv-$id',
      events: [
        TaskEvent(
          ts: start,
          stream: 'system',
          kind: 'system',
          text: 'Demo spell started with $_selectedAgent ($_selectedMode/$_selectedEffort)',
        ),
      ],
    );
    _upsertTask(task);
    _selectedTaskId = id;
    _setMood(WizardMood.casting, quip: 'Weaving "$prompt"...');

    final steps = [
      (
        const Duration(milliseconds: 650),
        TaskEvent(
          ts: DateTime.now(),
          stream: 'stdout',
          kind: 'tool',
          text: 'Inspecting workspace $_selectedWorkspace...',
        ),
      ),
      (
        const Duration(milliseconds: 1400),
        TaskEvent(
          ts: DateTime.now(),
          stream: 'stdout',
          kind: 'assistant',
          text: 'Analyzing Omarchy agent state and running checks...',
        ),
      ),
      (
        const Duration(milliseconds: 2300),
        TaskEvent(
          ts: DateTime.now(),
          stream: 'stdout',
          kind: 'result',
          text: '✨ Spell complete! "$prompt" finished with 0 warnings.',
        ),
      ),
    ];

    var stepIndex = 0;
    void scheduleNext() {
      if (_disposed || stepIndex >= steps.length) return;
      final (delay, ev) = steps[stepIndex];
      _demoTimer = Timer(
        stepIndex == 0 ? delay : const Duration(milliseconds: 850),
        () {
          if (_disposed) return;
          final currentIdx = _tasks.indexWhere((t) => t.id == id);
          if (currentIdx == -1 ||
              _tasks[currentIdx].status == TaskStatus.cancelled) {
            return;
          }
          _appendTaskEvent(id, ev);
          stepIndex++;
          if (stepIndex >= steps.length) {
            final finishedAt = DateTime.now();
            final elapsed =
                finishedAt.difference(start).inMilliseconds / 1000.0;
            final completed = _tasks[currentIdx].copyWith(
              status: TaskStatus.completed,
              finishedAt: finishedAt,
              durationSeconds: double.parse(elapsed.toStringAsFixed(2)),
              exitCode: 0,
              summary: ev.text,
            );
            _upsertTask(completed);
            _onTaskTerminal(completed, success: true);
          } else {
            scheduleNext();
          }
        },
      );
    }

    scheduleNext();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _celebrateResetTimer?.cancel();
    _demoTimer?.cancel();
    _batteryTimer?.cancel();
    unawaited(_disconnectSocket());
    super.dispose();
  }
}
