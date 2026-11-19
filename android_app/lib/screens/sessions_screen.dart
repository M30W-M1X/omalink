import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/agent_session.dart';
import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({
    super.key,
    required this.client,
  });

  final BridgeClient client;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.client.refreshSessions());
  }

  void _openPeek(AgentSession session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionPeekScreen(
          client: widget.client,
          initialSession: session,
        ),
      ),
    );
  }

  Future<void> _confirmAndClose(AgentSession session) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WizardColors.surfaceCard,
        title: Text(
          session.isOpen ? 'Close Live Session?' : 'Dismiss Session?',
          style: TextStyle(color: WizardColors.textPrimary),
        ),
        content: Text(
          session.isOpen
              ? 'This will close the running "${session.title}" agent process/window on Omarchy and remove it from OmaLink.'
              : 'Remove "${session.title}" from your OmaLink sessions list? It will reappear automatically if new activity occurs.',
          style: TextStyle(color: WizardColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WizardColors.coralError,
              foregroundColor: WizardColors.obsidian,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(session.isOpen ? 'Close Session' : 'Dismiss'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await widget.client.closeSession(session);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          err ??
              (session.isOpen
                  ? 'Closed "${session.title}" on Omarchy'
                  : 'Dismissed "${session.title}"'),
        ),
        backgroundColor: err != null ? WizardColors.coralError : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.client,
      builder: (context, _) {
        final sessions = widget.client.sessions;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Live Agent Sessions'),
            actions: [
              IconButton(
                tooltip: 'Refresh Sessions',
                onPressed: widget.client.sessionsLoading
                    ? null
                    : () => widget.client.refreshSessions(),
                icon: widget.client.sessionsLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.refresh_rounded, color: WizardColors.cyanArcane),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => widget.client.refreshSessions(),
            child: sessions.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 48),
                      Icon(
                        Icons.forum_outlined,
                        size: 52,
                        color: WizardColors.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No active or recent AI sessions detected yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: WizardColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Start agy or claude on your Omarchy desktop and pull down to peek in, receive alerts when it needs a response, or continue building from your phone.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: WizardColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final s = sessions[index];
                      return _SessionCard(
                        session: s,
                        onTap: () => _openPeek(s),
                        onClose: () => _confirmAndClose(s),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onTap,
    required this.onClose,
  });

  final AgentSession session;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (Color badgeColor, String badgeLabel, IconData badgeIcon) =
        session.needsResponse
            ? (
                WizardColors.goldStarlight,
                'NEEDS RESPONSE',
                Icons.mark_chat_unread_rounded,
              )
            : session.isRunning
                ? (
                    WizardColors.cyanArcane,
                    'RUNNING',
                    Icons.bolt_rounded,
                  )
                : session.isError
                    ? (
                        WizardColors.coralError,
                        'ERROR',
                        Icons.error_outline_rounded,
                      )
                    : session.isOpen
                        ? (
                            WizardColors.emeraldSage,
                            'OPEN',
                            Icons.terminal_rounded,
                          )
                        : (
                            WizardColors.textMuted,
                            'IDLE',
                            Icons.history_rounded,
                          );

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: session.needsResponse
              ? WizardColors.goldStarlight.withValues(alpha: 0.7)
              : session.isRunning
                  ? WizardColors.cyanArcane.withValues(alpha: 0.5)
                  : WizardColors.borderSubtle,
          width: session.needsResponse ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, size: 13, color: badgeColor),
                        const SizedBox(width: 4),
                        Text(
                          badgeLabel,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: WizardColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      session.agent.toUpperCase(),
                      style: TextStyle(
                        color: WizardColors.violetArcane,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (session.canSendTerminal) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.desktop_windows_outlined,
                      size: 14,
                      color: WizardColors.emeraldSage,
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: session.isOpen ? 'Close Session' : 'Dismiss Session',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: onClose,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: WizardColors.textMuted,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: WizardColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                session.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WizardColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                session.shortWorkspace,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WizardColors.textMuted,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              if (session.lastActivity.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: WizardColors.midnight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    session.lastActivity,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: session.needsResponse
                          ? WizardColors.goldStarlight
                          : WizardColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SessionPeekScreen extends StatefulWidget {
  const SessionPeekScreen({
    super.key,
    required this.client,
    required this.initialSession,
  });

  final BridgeClient client;
  final AgentSession initialSession;

  @override
  State<SessionPeekScreen> createState() => _SessionPeekScreenState();
}

class _SessionPeekScreenState extends State<SessionPeekScreen> {
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<SessionTranscriptMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  bool _useLiveTerminal = false;
  Timer? _pollTimer;

  AgentSession get _session {
    for (final s in widget.client.sessions) {
      if (s.id == widget.initialSession.id) return s;
    }
    return widget.initialSession;
  }

  @override
  void initState() {
    super.initState();
    _useLiveTerminal = widget.initialSession.canSendTerminal &&
        widget.initialSession.needsResponse;
    unawaited(_loadTranscript(scrollToBottom: true));
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        unawaited(_loadTranscript(scrollToBottom: false));
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTranscript({bool scrollToBottom = false}) async {
    final msgs = await widget.client.fetchSessionTranscript(_session);
    if (!mounted) return;
    final hadCount = _messages.length;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
    if (scrollToBottom || msgs.length > hadCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendReply(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    _replyController.clear();
    final err = await widget.client.sendSessionReply(
      session: _session,
      message: msg,
      viaLiveTerminal: _useLiveTerminal && _session.canSendTerminal,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(err), backgroundColor: WizardColors.coralError),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _useLiveTerminal && _session.canSendTerminal
                ? 'Sent directly to live terminal window!'
                : 'Sent to ${_session.agent} session — continuing now!',
          ),
        ),
      );
      await _loadTranscript(scrollToBottom: true);
    }
  }

  Future<void> _confirmAndCloseCurrent() async {
    final s = _session;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WizardColors.surfaceCard,
        title: Text(
          s.isOpen ? 'Close Live Session?' : 'Dismiss Session?',
          style: TextStyle(color: WizardColors.textPrimary),
        ),
        content: Text(
          s.isOpen
              ? 'This will close the running "${s.title}" agent process/window on Omarchy and remove it from OmaLink.'
              : 'Remove "${s.title}" from your OmaLink sessions list?',
          style: TextStyle(color: WizardColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WizardColors.coralError,
              foregroundColor: WizardColors.obsidian,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.isOpen ? 'Close Session' : 'Dismiss'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await widget.client.closeSession(s);
    if (!mounted) return;
    if (err != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(err), backgroundColor: WizardColors.coralError),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('Closed "${s.title}"')),
      );
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.client,
      builder: (context, _) {
        final s = _session;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${s.agent.toUpperCase()} • ${s.state.replaceAll('_', ' ').toUpperCase()} • ${s.shortWorkspace}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: WizardColors.textMuted),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: s.isOpen ? 'Close Session' : 'Dismiss Session',
                onPressed: _confirmAndCloseCurrent,
                icon: Icon(Icons.power_settings_new_rounded, color: WizardColors.coralError),
              ),
              IconButton(
                tooltip: 'Refresh Transcript',
                onPressed: () => _loadTranscript(scrollToBottom: true),
                icon: Icon(Icons.refresh_rounded, color: WizardColors.cyanArcane),
              ),
            ],
          ),
          body: Column(
            children: [
              if (s.pendingQuestions.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: WizardColors.goldStarlight.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: WizardColors.goldStarlight.withValues(alpha: 0.65),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.mark_chat_unread_rounded,
                            size: 16,
                            color: WizardColors.goldStarlight,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'NEEDS YOUR RESPONSE',
                            style: TextStyle(
                              color: WizardColors.goldStarlight,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.pendingQuestions.first.question,
                        style: TextStyle(
                          color: WizardColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (s.pendingQuestions.first.options.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: s.pendingQuestions.first.options
                              .map(
                                (opt) => ActionChip(
                                  backgroundColor: WizardColors.surfaceCard,
                                  label: Text(
                                    opt,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: WizardColors.cyanArcane,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: _sending ? null : () => _sendReply(opt),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(
                            child: Text(
                              'No transcript entries recorded yet.',
                              style: TextStyle(color: WizardColors.textMuted),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              return _TranscriptBubble(msg: _messages[index]);
                            },
                          ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: WizardColors.surfaceCard,
                  border: Border(
                    top: BorderSide(color: WizardColors.borderSubtle),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (s.canSendTerminal) ...[
                              ChoiceChip(
                                label: const Text('Live Terminal'),
                                selected: _useLiveTerminal,
                                onSelected: (v) => setState(() => _useLiveTerminal = v),
                              ),
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: const Text('Resume CLI'),
                                selected: !_useLiveTerminal,
                                onSelected: (v) => setState(() => _useLiveTerminal = !v),
                              ),
                              const SizedBox(width: 8),
                            ],
                            for (final quick in const [
                              'Continue',
                              'Yes, proceed',
                              'Run tests & verify',
                            ]) ...[
                              ActionChip(
                                label: Text(quick, style: const TextStyle(fontSize: 11)),
                                onPressed: _sending ? null : () => _sendReply(quick),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyController,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.send,
                              onSubmitted: _sendReply,
                              decoration: InputDecoration(
                                hintText: _useLiveTerminal && s.canSendTerminal
                                    ? 'Type directly into live desktop terminal...'
                                    : 'Reply or tell ${s.agent} to continue...',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _sending
                                ? null
                                : () => _sendReply(_replyController.text),
                            style: FilledButton.styleFrom(
                              backgroundColor: WizardColors.cyanArcane,
                              foregroundColor: WizardColors.obsidian,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                            ),
                            child: _sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send_rounded, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({required this.msg});

  final SessionTranscriptMessage msg;

  @override
  Widget build(BuildContext context) {
    if (msg.role == 'tool' || msg.role == 'tool_output') {
      final isOut = msg.role == 'tool_output';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: WizardColors.midnight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: WizardColors.borderSubtle.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isOut ? Icons.terminal_rounded : Icons.build_circle_outlined,
                size: 14,
                color: isOut ? WizardColors.emeraldSage : WizardColors.violetArcane,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  msg.text,
                  maxLines: isOut ? 5 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: WizardColors.textMuted,
                    fontSize: 11,
                    fontFamily: isOut ? 'monospace' : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isUser = msg.role == 'user';
    final isQuestion = msg.role == 'question';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? WizardColors.violetArcane.withValues(alpha: 0.24)
              : isQuestion
                  ? WizardColors.goldStarlight.withValues(alpha: 0.16)
                  : WizardColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUser
                ? WizardColors.violetArcane.withValues(alpha: 0.5)
                : isQuestion
                    ? WizardColors.goldStarlight.withValues(alpha: 0.65)
                    : WizardColors.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser
                  ? 'YOU'
                  : isQuestion
                      ? 'AGENT QUESTION'
                      : 'AGENT',
              style: TextStyle(
                color: isUser
                    ? WizardColors.violetArcane
                    : isQuestion
                        ? WizardColors.goldStarlight
                        : WizardColors.cyanArcane,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              msg.text,
              style: TextStyle(
                color: WizardColors.textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
