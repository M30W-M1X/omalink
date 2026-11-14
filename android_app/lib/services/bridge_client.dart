import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/agent_task.dart';
import '../models/system_control.dart';
import '../models/wizard_mood.dart';
import 'notification_service.dart';
import 'settings_store.dart';

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

  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  Timer? _celebrateResetTimer;
  Timer? _demoTimer;
  bool _disposed = false;

  Future<void> init() async {
    _settings = await _settingsStore.load();
    _selectedMode = _settings.defaultMode;
    _selectedEffort = _settings.defaultEffort;
    if (_settings.demoMode) {
      _activateDemoMode();
    } else {
      await connect();
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
    await _settingsStore.save(next);
    _lastError = null;
    if (next.demoMode) {
      await _disconnectSocket();
      _activateDemoMode();
    } else {
      await connect();
    }
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
            _applyHostStatus(
              HostStatus.fromJson(data['status'] as Map<String, dynamic>),
            );
          }
          if (data['tasks'] is List) {
            _tasks
              ..clear()
              ..addAll(
                (data['tasks'] as List)
                    .whereType<Map<String, dynamic>>()
                    .map(AgentTask.fromJson),
              );
          }
          _syncMoodFromTasks();
          break;
        case 'task.started':
          final task = AgentTask.fromJson(data);
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
    if (_settings.notifyOnComplete) {
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
      case 'theme.set':
        final name = params['name']?.toString() ?? s.theme.current;
        _systemState = s.copyWith(theme: s.theme.copyWith(current: name));
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
    unawaited(_disconnectSocket());
    super.dispose();
  }
}
