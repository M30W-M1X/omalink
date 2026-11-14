import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';

enum _PtyState {
  demo,
  disconnected,
  connecting,
  connected,
}

const TerminalTheme _omarchyTerminalTheme = TerminalTheme(
  cursor: WizardColors.cyanArcane,
  selection: Color(0x557DCFFF),
  foreground: WizardColors.textPrimary,
  background: WizardColors.obsidian,
  black: Color(0xFF15161E),
  red: WizardColors.coralError,
  green: WizardColors.emeraldSage,
  yellow: WizardColors.goldStarlight,
  blue: Color(0xFF7AA2F7),
  magenta: WizardColors.violetArcane,
  cyan: WizardColors.cyanArcane,
  white: Color(0xFFA9B1D6),
  brightBlack: Color(0xFF414868),
  brightRed: Color(0xFFF7768E),
  brightGreen: Color(0xFF9ECE6A),
  brightYellow: Color(0xFFE0AF68),
  brightBlue: Color(0xFF7AA2F7),
  brightMagenta: Color(0xFFBB9AF7),
  brightCyan: Color(0xFF7DCFFF),
  brightWhite: Color(0xFFC0CAF5),
  searchHitBackground: Color(0x66E0AF68),
  searchHitBackgroundCurrent: Color(0x997DCFFF),
  searchHitForeground: WizardColors.obsidian,
);

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.client,
    required this.isActive,
    required this.onOpenSettings,
  });

  final BridgeClient client;
  final bool isActive;
  final VoidCallback onOpenSettings;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  final TerminalController _controller = TerminalController();
  final FocusNode _focusNode = FocusNode();

  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  _PtyState _ptyState = _PtyState.disconnected;
  String _statusDetail = 'Not connected';
  String _activeCwd = '~';
  double _fontSize = 13.0;
  bool _ctrlActive = false;
  bool _hasAutoConnected = false;
  bool _wasDemoMode = true;
  final StringBuffer _demoLineBuffer = StringBuffer();

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 3000,
      onOutput: _handleTerminalOutput,
      onResize: _handleTerminalResize,
    );
    widget.client.addListener(_onClientChanged);
    _wasDemoMode = widget.client.settings.demoMode;
    if (_wasDemoMode) {
      _enterDemoShell();
    } else if (widget.isActive) {
      _hasAutoConnected = true;
      unawaited(_connect());
    }
  }

  @override
  void didUpdateWidget(covariant TerminalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stagedCwd = widget.client.consumePendingTerminalCwd();
    if (stagedCwd != null) {
      _hasAutoConnected = true;
      unawaited(_connect(cwd: stagedCwd));
      return;
    }
    if (widget.isActive &&
        !oldWidget.isActive &&
        !widget.client.settings.demoMode &&
        !_hasAutoConnected &&
        _ptyState == _PtyState.disconnected) {
      _hasAutoConnected = true;
      unawaited(_connect());
    }
  }

  void _onClientChanged() {
    final stagedCwd = widget.client.consumePendingTerminalCwd();
    if (stagedCwd != null) {
      _hasAutoConnected = true;
      unawaited(_connect(cwd: stagedCwd));
      return;
    }
    final isDemo = widget.client.settings.demoMode;
    if (isDemo != _wasDemoMode) {
      _wasDemoMode = isDemo;
      if (isDemo) {
        unawaited(_disconnect(silent: true));
        _enterDemoShell();
      } else {
        _ptyState = _PtyState.disconnected;
        _statusDetail = 'Tap Connect to start shell';
        if (mounted) setState(() {});
        if (widget.isActive) {
          _hasAutoConnected = true;
          unawaited(_connect());
        }
      }
    }
  }

  void _enterDemoShell() {
    _ptyState = _PtyState.demo;
    _activeCwd = '~';
    _statusDetail = 'Demo Familiar Shell';
    _demoLineBuffer.clear();
    _terminal.write('\x1b[2J\x1b[H');
    _terminal.write(
      '\x1b[35m✨ Omarchy Wizard Remote Terminal (Demo Familiar Mode)\x1b[0m\r\n'
      '\x1b[90mPair with your live bridge in Sanctum for a real Omarchy login shell.\x1b[0m\r\n'
      '\x1b[90mTry: help, ls, uname -a, pwd, clear\x1b[0m\r\n\r\n',
    );
    _writeDemoPrompt();
    if (mounted) setState(() {});
  }

  void _writeDemoPrompt() {
    _terminal.write(
      '\x1b[36mkitsune@omarchy\x1b[0m:\x1b[35m$_activeCwd\x1b[0m\$ ',
    );
  }

  void _handleTerminalOutput(String raw) {
    var data = raw;
    if (_ctrlActive && raw.length == 1) {
      final lower = raw.toLowerCase().codeUnitAt(0);
      if (lower >= 97 && lower <= 122) {
        data = String.fromCharCode(lower - 96);
      }
      if (mounted) {
        setState(() => _ctrlActive = false);
      } else {
        _ctrlActive = false;
      }
    }

    if (widget.client.settings.demoMode || _ptyState == _PtyState.demo) {
      _handleDemoInput(data);
      return;
    }

    final ws = _ws;
    if (ws != null && _ptyState == _PtyState.connected) {
      try {
        ws.add(jsonEncode({'type': 'input', 'data': data}));
      } catch (_) {}
    }
  }

  void _handleDemoInput(String data) {
    for (final rune in data.runes) {
      if (rune == 3) {
        // Ctrl+C
        _demoLineBuffer.clear();
        _terminal.write('^C\r\n');
        _writeDemoPrompt();
      } else if (rune == 12) {
        // Ctrl+L
        _terminal.write('\x1b[2J\x1b[H');
        _writeDemoPrompt();
        _terminal.write(_demoLineBuffer.toString());
      } else if (rune == 13 || rune == 10) {
        final cmd = _demoLineBuffer.toString().trim();
        _demoLineBuffer.clear();
        _terminal.write('\r\n');
        _executeDemoCommand(cmd);
        _writeDemoPrompt();
      } else if (rune == 127 || rune == 8) {
        final current = _demoLineBuffer.toString();
        if (current.isNotEmpty) {
          _demoLineBuffer
            ..clear()
            ..write(current.substring(0, current.length - 1));
          _terminal.write('\b \b');
        }
      } else if (rune >= 32) {
        final ch = String.fromCharCode(rune);
        _demoLineBuffer.write(ch);
        _terminal.write(ch);
      }
    }
  }

  void _executeDemoCommand(String cmd) {
    if (cmd.isEmpty) return;
    if (cmd == 'clear') {
      _terminal.write('\x1b[2J\x1b[H');
    } else if (cmd == 'help') {
      _terminal.write(
        'Available demo commands: help, ls, pwd, uname -a, whoami, clear\r\n',
      );
    } else if (cmd == 'pwd') {
      _terminal.write('${_activeCwd == '~' ? '/home/wizard' : _activeCwd}\r\n');
    } else if (cmd == 'whoami') {
      _terminal.write('wizard\r\n');
    } else if (cmd == 'uname -a') {
      _terminal.write('Linux kitsune 6.13.4-arch1-1 #1 SMP PREEMPT_DYNAMIC x86_64 GNU/Linux\r\n');
    } else if (cmd.startsWith('ls')) {
      _terminal.write(
        '\x1b[36mProjects/\x1b[0m  \x1b[36m.config/\x1b[0m  README.md  omarchy_wizard.sh\r\n',
      );
    } else if (cmd.startsWith('cd ')) {
      final target = cmd.substring(3).trim();
      if (target.isNotEmpty) {
        _activeCwd = target;
      }
    } else {
      _terminal.write('demo: executed "$cmd"\r\n');
    }
  }

  void _handleTerminalResize(int width, int height, int pixelWidth, int pixelHeight) {
    final ws = _ws;
    if (ws != null && _ptyState == _PtyState.connected) {
      try {
        ws.add(jsonEncode({
          'type': 'resize',
          'cols': width,
          'rows': height,
        }));
      } catch (_) {}
    }
  }

  Future<void> _connect({String? cwd}) async {
    if (widget.client.settings.demoMode) {
      if (cwd != null && cwd.isNotEmpty) {
        _activeCwd = cwd;
        _terminal.write('\r\n\x1b[90mcd $cwd\x1b[0m\r\n');
        _writeDemoPrompt();
      } else {
        _enterDemoShell();
      }
      return;
    }

    await _disconnect(silent: true);

    final settings = widget.client.settings;
    if (mounted) {
      setState(() {
        _ptyState = _PtyState.connecting;
        _statusDetail = 'Connecting to ${settings.host}...';
      });
    }

    final cols = _terminal.viewWidth > 0 ? _terminal.viewWidth : 80;
    final rows = _terminal.viewHeight > 0 ? _terminal.viewHeight : 24;
    final targetCwd = cwd ?? _activeCwd;

    final queryParams = <String, String>{
      'cols': '$cols',
      'rows': '$rows',
      if (settings.token.isNotEmpty) 'token': settings.token,
      if (targetCwd.isNotEmpty && targetCwd != '~') 'cwd': targetCwd,
    };

    final uri = Uri.parse(settings.terminalWsUrl).replace(queryParameters: queryParams);

    try {
      final ws = await WebSocket.connect(
        uri.toString(),
        headers: settings.token.isNotEmpty
            ? {'Authorization': 'Bearer ${settings.token}'}
            : null,
      ).timeout(const Duration(seconds: 6));

      _ws = ws;
      _terminal.write('\x1b[2J\x1b[H');

      _wsSub = ws.listen(
        (raw) {
          if (raw is! String) return;
          try {
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            final type = decoded['type'] as String? ?? '';
            if (type == 'ready') {
              final shellCwd = decoded['cwd'] as String? ?? '~';
              if (mounted) {
                setState(() {
                  _ptyState = _PtyState.connected;
                  _activeCwd = shellCwd;
                  _statusDetail = shellCwd;
                });
              }
            } else if (type == 'output') {
              final chunk = decoded['data'] as String? ?? '';
              if (chunk.isNotEmpty) {
                _terminal.write(chunk);
              }
            } else if (type == 'exit') {
              final code = decoded['code'];
              _terminal.write('\r\n\x1b[33m[Shell exited with code $code]\x1b[0m\r\n');
              unawaited(_disconnect(reason: 'Exited ($code)'));
            } else if (type == 'error') {
              final msg = decoded['message'] as String? ?? 'Terminal error';
              _terminal.write('\r\n\x1b[31m$msg\x1b[0m\r\n');
            }
          } catch (_) {}
        },
        onError: (err) {
          _terminal.write('\r\n\x1b[31m[Connection error: $err]\x1b[0m\r\n');
          unawaited(_disconnect(reason: 'Connection error'));
        },
        onDone: () {
          if (_ptyState != _PtyState.disconnected) {
            _terminal.write('\r\n\x1b[90m[Terminal disconnected]\x1b[0m\r\n');
            unawaited(_disconnect(reason: 'Disconnected'));
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      _terminal.write('\r\n\x1b[31mFailed to open terminal: $e\x1b[0m\r\n');
      if (mounted) {
        setState(() {
          _ptyState = _PtyState.disconnected;
          _statusDetail = 'Connection failed';
        });
      }
    }
  }

  Future<void> _disconnect({bool silent = false, String reason = 'Disconnected'}) async {
    await _wsSub?.cancel();
    _wsSub = null;
    final ws = _ws;
    _ws = null;
    if (ws != null) {
      try {
        await ws.close();
      } catch (_) {}
    }
    if (!silent && mounted) {
      setState(() {
        _ptyState = widget.client.settings.demoMode
            ? _PtyState.demo
            : _PtyState.disconnected;
        _statusDetail = reason;
      });
    }
  }

  void _sendSequence(String seq) {
    _handleTerminalOutput(seq);
    _focusNode.requestFocus();
  }

  Future<void> _pasteClipboard() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text;
    if (text != null && text.isNotEmpty) {
      _terminal.paste(text);
    }
    _focusNode.requestFocus();
  }

  Color _stateColor() {
    switch (_ptyState) {
      case _PtyState.connected:
        return WizardColors.emeraldSage;
      case _PtyState.connecting:
        return WizardColors.goldStarlight;
      case _PtyState.demo:
        return WizardColors.cyanArcane;
      case _PtyState.disconnected:
        return WizardColors.coralError;
    }
  }

  String _shortCwd(String path) {
    if (path.length <= 28) return path;
    return '…${path.substring(path.length - 27)}';
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClientChanged);
    unawaited(_disconnect(silent: true));
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = widget.client.settings.demoMode;
    final badgeColor = _stateColor();

    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: const BoxDecoration(
              color: WizardColors.midnight,
              border: Border(bottom: BorderSide(color: WizardColors.borderSubtle)),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Omarchy Terminal',
                        style: TextStyle(
                          color: WizardColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _shortCwd(_statusDetail),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WizardColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Decrease Font',
                  visualDensity: VisualDensity.compact,
                  onPressed: _fontSize <= 10
                      ? null
                      : () => setState(() => _fontSize -= 1),
                  icon: const Icon(Icons.text_decrease_rounded, size: 18, color: WizardColors.textMuted),
                ),
                IconButton(
                  tooltip: 'Increase Font',
                  visualDensity: VisualDensity.compact,
                  onPressed: _fontSize >= 19
                      ? null
                      : () => setState(() => _fontSize += 1),
                  icon: const Icon(Icons.text_increase_rounded, size: 18, color: WizardColors.textMuted),
                ),
                IconButton(
                  tooltip: 'Clear Screen',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _terminal.write('\x1b[2J\x1b[H');
                    if (isDemo) _writeDemoPrompt();
                  },
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18, color: WizardColors.textMuted),
                ),
                if (isDemo)
                  TextButton(
                    onPressed: widget.onOpenSettings,
                    child: const Text('Pair Live'),
                  )
                else if (_ptyState == _PtyState.connected ||
                    _ptyState == _PtyState.connecting)
                  IconButton(
                    tooltip: 'Disconnect Shell',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(_disconnect()),
                    icon: const Icon(Icons.link_off_rounded, size: 20, color: WizardColors.coralError),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => unawaited(_connect()),
                    style: FilledButton.styleFrom(
                      backgroundColor: WizardColors.cyanArcane,
                      foregroundColor: WizardColors.obsidian,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    icon: const Icon(Icons.terminal_rounded, size: 16),
                    label: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              child: TerminalView(
                _terminal,
                controller: _controller,
                focusNode: _focusNode,
                theme: _omarchyTerminalTheme,
                textStyle: TerminalStyle(fontSize: _fontSize),
                autofocus: false,
                alwaysShowCursor: true,
                padding: const EdgeInsets.all(6),
              ),
            ),
          ),
          Container(
            height: 44,
            decoration: const BoxDecoration(
              color: WizardColors.midnight,
              border: Border(top: BorderSide(color: WizardColors.borderSubtle)),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                _QuickKeyChip(
                  label: 'CTRL',
                  active: _ctrlActive,
                  onTap: () {
                    setState(() => _ctrlActive = !_ctrlActive);
                    _focusNode.requestFocus();
                  },
                ),
                _QuickKeyChip(label: 'ESC', onTap: () => _sendSequence('\x1b')),
                _QuickKeyChip(label: 'TAB', onTap: () => _sendSequence('\t')),
                _QuickKeyChip(label: '^C', onTap: () => _sendSequence('\x03')),
                _QuickKeyChip(label: '^D', onTap: () => _sendSequence('\x04')),
                _QuickKeyChip(label: '^L', onTap: () => _sendSequence('\x0c')),
                _QuickKeyChip(label: '↑', onTap: () => _sendSequence('\x1b[A')),
                _QuickKeyChip(label: '↓', onTap: () => _sendSequence('\x1b[B')),
                _QuickKeyChip(label: '←', onTap: () => _sendSequence('\x1b[D')),
                _QuickKeyChip(label: '→', onTap: () => _sendSequence('\x1b[C')),
                _QuickKeyChip(label: '~/', onTap: () => _sendSequence('~/')),
                _QuickKeyChip(label: 'PASTE', onTap: () => unawaited(_pasteClipboard())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickKeyChip extends StatelessWidget {
  const _QuickKeyChip({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? WizardColors.violetArcane : WizardColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: active ? WizardColors.obsidian : WizardColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
