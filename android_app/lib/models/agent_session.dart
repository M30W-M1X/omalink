class SessionQuestion {
  const SessionQuestion({
    required this.question,
    this.options = const [],
    this.isMultiSelect = false,
  });

  final String question;
  final List<String> options;
  final bool isMultiSelect;

  factory SessionQuestion.fromJson(Map<String, dynamic> json) {
    return SessionQuestion(
      question: json['question']?.toString() ?? '',
      options: (json['options'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      isMultiSelect: json['is_multi_select'] == true,
    );
  }
}

class AgentSession {
  const AgentSession({
    required this.id,
    required this.agent,
    required this.title,
    required this.workspace,
    required this.state,
    this.isOpen = false,
    this.windowAddress = '',
    this.stepCount = 0,
    this.updatedAt = '',
    this.lastActivity = '',
    this.pendingQuestions = const [],
    this.canResume = true,
    this.canSendTerminal = false,
  });

  final String id;
  final String agent;
  final String title;
  final String workspace;
  final String state; // needs_response | running | error | idle
  final bool isOpen;
  final String windowAddress;
  final int stepCount;
  final String updatedAt;
  final String lastActivity;
  final List<SessionQuestion> pendingQuestions;
  final bool canResume;
  final bool canSendTerminal;

  bool get needsResponse => state == 'needs_response';
  bool get isRunning => state == 'running';
  bool get isError => state == 'error';

  String get shortWorkspace {
    if (workspace.isEmpty) return '~';
    final parts = workspace.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return workspace;
    return '~/${parts.sublist(parts.length - 2).join('/')}';
  }

  AgentSession copyWith({
    String? state,
    String? lastActivity,
    List<SessionQuestion>? pendingQuestions,
    int? stepCount,
  }) {
    return AgentSession(
      id: id,
      agent: agent,
      title: title,
      workspace: workspace,
      state: state ?? this.state,
      isOpen: isOpen,
      windowAddress: windowAddress,
      stepCount: stepCount ?? this.stepCount,
      updatedAt: updatedAt,
      lastActivity: lastActivity ?? this.lastActivity,
      pendingQuestions: pendingQuestions ?? this.pendingQuestions,
      canResume: canResume,
      canSendTerminal: canSendTerminal,
    );
  }

  factory AgentSession.fromJson(Map<String, dynamic> json) {
    return AgentSession(
      id: json['id']?.toString() ?? '',
      agent: json['agent']?.toString() ?? 'agy',
      title: json['title']?.toString() ?? 'Agent Session',
      workspace: json['workspace']?.toString() ?? '',
      state: json['state']?.toString() ?? 'idle',
      isOpen: json['is_open'] == true,
      windowAddress: json['window_address']?.toString() ?? '',
      stepCount: (json['step_count'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at']?.toString() ?? '',
      lastActivity: json['last_activity']?.toString() ?? '',
      pendingQuestions: (json['pending_questions'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => SessionQuestion.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      canResume: json['can_resume'] != false,
      canSendTerminal: json['can_send_terminal'] == true,
    );
  }

  static List<AgentSession> demoList() {
    return const [
      AgentSession(
        id: 'demo-agy-build',
        agent: 'agy',
        title: 'OmaLink Marketplace Build',
        workspace: '/home/omarchy/Projects/omalink',
        state: 'needs_response',
        isOpen: true,
        windowAddress: '0xdeadbeef',
        stepCount: 42,
        updatedAt: 'just now',
        lastActivity: 'Question: Ready to tag and publish v3.1.0 to GitHub Releases?',
        pendingQuestions: [
          SessionQuestion(
            question: 'Ready to tag and publish v3.1.0 to GitHub Releases?',
            options: [
              'Yes, tag & publish now',
              'Run tests one more time first',
            ],
          ),
        ],
        canResume: true,
        canSendTerminal: true,
      ),
      AgentSession(
        id: 'demo-agy-tests',
        agent: 'agy',
        title: 'Hyprland Bar Plugin Refactor',
        workspace: '/home/omarchy/Projects/omalink',
        state: 'running',
        isOpen: true,
        stepCount: 19,
        updatedAt: '1m ago',
        lastActivity: 'Running: flutter test && omarchy plugin validate .',
        canResume: true,
      ),
    ];
  }
}

class SessionTranscriptMessage {
  const SessionTranscriptMessage({
    required this.step,
    required this.role,
    required this.text,
    this.toolName = '',
    this.status = '',
    this.createdAt = '',
    this.questions = const [],
  });

  final int step;
  final String role; // user | assistant | tool | tool_output | question
  final String text;
  final String toolName;
  final String status;
  final String createdAt;
  final List<SessionQuestion> questions;

  factory SessionTranscriptMessage.fromJson(Map<String, dynamic> json) {
    return SessionTranscriptMessage(
      step: (json['step'] as num?)?.toInt() ?? 0,
      role: json['role']?.toString() ?? 'assistant',
      text: json['text']?.toString() ?? '',
      toolName: json['tool_name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      questions: (json['questions'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => SessionQuestion.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }

  static List<SessionTranscriptMessage> demoTranscript(String id) {
    if (id == 'demo-agy-build') {
      return const [
        SessionTranscriptMessage(
          step: 1,
          role: 'user',
          text: 'Finish the live session monitor and ask me before publishing v3.1.0.',
        ),
        SessionTranscriptMessage(
          step: 2,
          role: 'tool',
          toolName: 'run_command',
          text: 'Running: flutter analyze && flutter test',
        ),
        SessionTranscriptMessage(
          step: 3,
          role: 'tool_output',
          text: 'No issues found! All 6 Flutter tests passed.',
        ),
        SessionTranscriptMessage(
          step: 4,
          role: 'question',
          toolName: 'ask_question',
          text: 'Ready to tag and publish v3.1.0 to GitHub Releases?',
          questions: [
            SessionQuestion(
              question: 'Ready to tag and publish v3.1.0 to GitHub Releases?',
              options: [
                'Yes, tag & publish now',
                'Run tests one more time first',
              ],
            ),
          ],
        ),
      ];
    }
    return const [
      SessionTranscriptMessage(
        step: 1,
        role: 'user',
        text: 'Refactor omalink.panel to auto-start the bridge service.',
      ),
      SessionTranscriptMessage(
        step: 2,
        role: 'tool',
        toolName: 'edit_file',
        text: 'Editing: Panel.qml',
      ),
      SessionTranscriptMessage(
        step: 3,
        role: 'assistant',
        text: 'Updated Panel.qml and validating the manifest now...',
      ),
    ];
  }
}
