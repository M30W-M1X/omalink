enum TaskStatus {
  running,
  completed,
  failed,
  cancelled;

  static TaskStatus fromWire(String? value) {
    switch (value) {
      case 'completed':
        return TaskStatus.completed;
      case 'failed':
        return TaskStatus.failed;
      case 'cancelled':
        return TaskStatus.cancelled;
      case 'running':
      default:
        return TaskStatus.running;
    }
  }

  bool get isTerminal => this != TaskStatus.running;

  String get displayLabel {
    switch (this) {
      case TaskStatus.running:
        return 'Casting';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.failed:
        return 'Failed';
      case TaskStatus.cancelled:
        return 'Cancelled';
    }
  }
}

class TaskEvent {
  TaskEvent({
    required this.ts,
    required this.stream,
    required this.kind,
    required this.text,
    this.conversationId,
  });

  final DateTime ts;
  final String stream;
  final String kind;
  final String text;
  final String? conversationId;

  factory TaskEvent.fromJson(Map<String, dynamic> json) {
    return TaskEvent(
      ts: DateTime.tryParse(json['ts']?.toString() ?? '') ?? DateTime.now(),
      stream: json['stream']?.toString() ?? 'stdout',
      kind: json['kind']?.toString() ?? 'text',
      text: json['text']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString(),
    );
  }
}

class AgentTask {
  AgentTask({
    required this.id,
    required this.prompt,
    required this.agent,
    required this.mode,
    required this.effort,
    required this.cwd,
    required this.status,
    required this.createdAt,
    this.finishedAt,
    this.durationSeconds,
    this.exitCode,
    this.summary = '',
    this.conversationId,
    List<TaskEvent>? events,
  }) : events = events ?? <TaskEvent>[];

  final String id;
  final String prompt;
  final String agent;
  final String mode;
  final String effort;
  final String cwd;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final double? durationSeconds;
  final int? exitCode;
  final String summary;
  final String? conversationId;
  final List<TaskEvent> events;

  factory AgentTask.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['events'];
    final parsedEvents = rawEvents is List
        ? rawEvents
            .whereType<Map<String, dynamic>>()
            .map(TaskEvent.fromJson)
            .toList()
        : <TaskEvent>[];

    return AgentTask(
      id: json['id']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      agent: json['agent']?.toString() ?? 'agy',
      mode: json['mode']?.toString() ?? 'auto',
      effort: json['effort']?.toString() ?? 'high',
      cwd: json['cwd']?.toString() ?? '~',
      status: TaskStatus.fromWire(json['status']?.toString()),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.now(),
      finishedAt: json['finished_at'] != null
          ? DateTime.tryParse(json['finished_at'].toString())
          : null,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      exitCode: (json['exit_code'] as num?)?.toInt(),
      summary: json['summary']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString(),
      events: parsedEvents,
    );
  }

  AgentTask copyWith({
    TaskStatus? status,
    DateTime? finishedAt,
    double? durationSeconds,
    int? exitCode,
    String? summary,
    String? conversationId,
    List<TaskEvent>? events,
  }) {
    return AgentTask(
      id: id,
      prompt: prompt,
      agent: agent,
      mode: mode,
      effort: effort,
      cwd: cwd,
      status: status ?? this.status,
      createdAt: createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      exitCode: exitCode ?? this.exitCode,
      summary: summary ?? this.summary,
      conversationId: conversationId ?? this.conversationId,
      events: events ?? this.events,
    );
  }
}

class HostStatus {
  const HostStatus({
    required this.hostname,
    required this.osName,
    required this.osVersion,
    required this.defaultAgent,
    required this.availableAgents,
    required this.workspaces,
    required this.runningTasks,
  });

  final String hostname;
  final String osName;
  final String osVersion;
  final String defaultAgent;
  final List<String> availableAgents;
  final List<String> workspaces;
  final int runningTasks;

  factory HostStatus.demo() => const HostStatus(
        hostname: 'omarchy-demo',
        osName: 'Omarchy',
        osVersion: '4.5.0',
        defaultAgent: 'agy',
        availableAgents: ['agy', 'claude', 'codex', 'kimi'],
        workspaces: ['~/Work', '~/Projects'],
        runningTasks: 0,
      );

  factory HostStatus.fromJson(Map<String, dynamic> json) {
    return HostStatus(
      hostname: json['hostname']?.toString() ?? 'omarchy',
      osName: json['os_name']?.toString() ?? 'Omarchy',
      osVersion: json['os_version']?.toString() ?? '',
      defaultAgent: json['default_agent']?.toString() ?? 'agy',
      availableAgents: (json['available_agents'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['agy'],
      workspaces: (json['workspaces'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['~/Work'],
      runningTasks: (json['running_tasks'] as num?)?.toInt() ?? 0,
    );
  }
}
