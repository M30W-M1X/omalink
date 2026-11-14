import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';

enum _TouchMode {
  leftClick,
  rightClick,
  drag,
}

enum _StreamPreset {
  fast(scale: 0.30, quality: 50, fps: 5, label: 'Fast'),
  crisp(scale: 0.50, quality: 70, fps: 3, label: 'Crisp');

  const _StreamPreset({
    required this.scale,
    required this.quality,
    required this.fps,
    required this.label,
  });

  final double scale;
  final int quality;
  final int fps;
  final String label;
}

class DesktopScreen extends StatefulWidget {
  const DesktopScreen({
    super.key,
    required this.client,
    this.onOpenSettings,
  });

  final BridgeClient client;
  final VoidCallback? onOpenSettings;

  @override
  State<DesktopScreen> createState() => _DesktopScreenState();
}

class _DesktopScreenState extends State<DesktopScreen> {
  final TransformationController _transformController = TransformationController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  bool _connecting = false;
  bool _connected = false;
  bool _paused = false;
  bool _showKeyboard = false;
  _TouchMode _touchMode = _TouchMode.leftClick;
  _StreamPreset _preset = _StreamPreset.fast;

  Uint8List? _latestFrame;
  String _statusText = 'Connecting...';
  int _monitorWidth = 1920;
  int _monitorHeight = 1080;
  String _selectedOutput = '';
  List<Map<String, dynamic>> _monitors = const [];
  List<Map<String, dynamic>> _workspaces = const [
    {'id': 1, 'name': '1'},
    {'id': 2, 'name': '2'},
    {'id': 3, 'name': '3'},
  ];
  int _activeWorkspace = 1;

  double _fpsEstimate = 0.0;
  DateTime? _lastFrameAt;
  Offset? _lastTapNormalized;
  Timer? _reticleTimer;
  String? _demoToast;

  @override
  void initState() {
    super.initState();
    if (widget.client.settings.demoMode) {
      _enterDemoDesktop();
    } else {
      unawaited(_connect());
    }
  }

  void _enterDemoDesktop() {
    setState(() {
      _connected = false;
      _connecting = false;
      _monitorWidth = 1920;
      _monitorHeight = 1080;
      _selectedOutput = 'DP-1 (Demo)';
      _statusText = 'Demo Familiar Desktop';
      _workspaces = const [
        {'id': 1, 'name': '1'},
        {'id': 2, 'name': '2'},
        {'id': 3, 'name': '3'},
        {'id': 4, 'name': '4'},
      ];
    });
  }

  Future<void> _connect() async {
    if (widget.client.settings.demoMode) {
      _enterDemoDesktop();
      return;
    }

    await _disconnect(silent: true);
    final settings = widget.client.settings;
    if (mounted) {
      setState(() {
        _connecting = true;
        _connected = false;
        _statusText = 'Connecting to ${settings.host}...';
      });
    }

    final uri = Uri.parse(settings.desktopWsUrl).replace(queryParameters: {
      'scale': '${_preset.scale}',
      'quality': '${_preset.quality}',
      'fps': '${_preset.fps}',
      if (_selectedOutput.isNotEmpty) 'output': _selectedOutput,
      if (settings.token.isNotEmpty) 'token': settings.token,
    });

    try {
      final ws = await WebSocket.connect(
        uri.toString(),
        headers: settings.token.isNotEmpty
            ? {'Authorization': 'Bearer ${settings.token}'}
            : null,
      ).timeout(const Duration(seconds: 6));

      _ws = ws;
      _wsSub = ws.listen(
        (raw) {
          if (raw is List<int>) {
            final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
            final now = DateTime.now();
            double fps = _fpsEstimate;
            if (_lastFrameAt != null) {
              final dtMs = now.difference(_lastFrameAt!).inMilliseconds;
              if (dtMs > 20) {
                final instant = 1000.0 / dtMs;
                fps = fps == 0 ? instant : (fps * 0.65 + instant * 0.35);
              }
            }
            _lastFrameAt = now;
            if (mounted) {
              setState(() {
                _latestFrame = bytes;
                _fpsEstimate = fps;
              });
            }
            return;
          }

          if (raw is String) {
            try {
              final msg = jsonDecode(raw) as Map<String, dynamic>;
              final type = msg['type'] as String? ?? '';
              if (type == 'ready' || type == 'layout') {
                final mon = msg['monitor'] as Map<String, dynamic>?;
                final rawMons = msg['monitors'] as List<dynamic>? ?? const [];
                final rawWs = msg['workspaces'] as List<dynamic>? ?? const [];
                if (mounted) {
                  setState(() {
                    _connecting = false;
                    _connected = true;
                    if (mon != null) {
                      _monitorWidth = (mon['width'] as num?)?.toInt() ?? _monitorWidth;
                      _monitorHeight = (mon['height'] as num?)?.toInt() ?? _monitorHeight;
                      _selectedOutput = (msg['output'] as String?) ??
                          (mon['name'] as String?) ??
                          _selectedOutput;
                      _activeWorkspace = (mon['active_workspace'] as num?)?.toInt() ??
                          _activeWorkspace;
                    }
                    _monitors = rawMons.cast<Map<String, dynamic>>();
                    if (rawWs.isNotEmpty) {
                      _workspaces = rawWs.cast<Map<String, dynamic>>();
                    }
                    _statusText = '$_selectedOutput • ${_monitorWidth}x$_monitorHeight';
                  });
                }
              }
            } catch (_) {}
          }
        },
        onError: (err) {
          unawaited(_disconnect(status: 'Error: $err'));
        },
        onDone: () {
          if (_connected || _connecting) {
            unawaited(_disconnect(status: 'Disconnected'));
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _connected = false;
          _statusText = 'Connection failed: $e';
        });
      }
    }
  }

  Future<void> _disconnect({bool silent = false, String status = 'Disconnected'}) async {
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
        _connecting = false;
        _connected = false;
        _statusText = status;
      });
    }
  }

  void _sendJson(Map<String, dynamic> payload) {
    if (widget.client.settings.demoMode) {
      setState(() {
        _demoToast = 'Demo event: ${payload['type']}';
      });
      return;
    }
    final ws = _ws;
    if (ws != null && _connected) {
      try {
        ws.add(jsonEncode(payload));
      } catch (_) {}
    }
  }

  void _showTapReticle(Offset normalized) {
    _reticleTimer?.cancel();
    setState(() {
      _lastTapNormalized = normalized;
    });
    _reticleTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) {
        setState(() => _lastTapNormalized = null);
      }
    });
  }

  Offset _normalizeLocal(Offset localPos, Size canvasSize) {
    final nx = (localPos.dx / canvasSize.width).clamp(0.0, 1.0);
    final ny = (localPos.dy / canvasSize.height).clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  void _onCanvasTapUp(TapUpDetails details, Size canvasSize) {
    final n = _normalizeLocal(details.localPosition, canvasSize);
    _showTapReticle(n);
    if (_touchMode == _TouchMode.rightClick) {
      _sendJson({
        'type': 'pointer',
        'action': 'right_click',
        'x': n.dx,
        'y': n.dy,
      });
    } else {
      _sendJson({
        'type': 'pointer',
        'action': 'tap',
        'button': 'left',
        'x': n.dx,
        'y': n.dy,
      });
    }
  }

  void _onCanvasLongPress(LongPressStartDetails details, Size canvasSize) {
    final n = _normalizeLocal(details.localPosition, canvasSize);
    _showTapReticle(n);
    _sendJson({
      'type': 'pointer',
      'action': 'right_click',
      'x': n.dx,
      'y': n.dy,
    });
  }

  void _sendText() {
    final text = _textController.text;
    if (text.isEmpty) return;
    _sendJson({'type': 'key', 'text': text});
    _textController.clear();
  }

  void _sendSpecialKey(String key, {List<String>? modifiers}) {
    _sendJson({
      'type': 'key',
      'key': key,
      if (modifiers != null && modifiers.isNotEmpty) 'modifiers': modifiers,
    });
  }

  void _switchPreset(_StreamPreset next) {
    setState(() => _preset = next);
    _sendJson({
      'type': 'config',
      'scale': next.scale,
      'quality': next.quality,
      'fps': next.fps,
    });
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _sendJson({'type': 'config', 'paused': _paused});
  }

  @override
  void dispose() {
    _reticleTimer?.cancel();
    unawaited(_disconnect(silent: true));
    _transformController.dispose();
    _textController.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = widget.client.settings.demoMode;
    final aspect = _monitorWidth > 0 && _monitorHeight > 0
        ? _monitorWidth / _monitorHeight
        : 16 / 9;

    return Scaffold(
      backgroundColor: WizardColors.obsidian,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
              decoration: const BoxDecoration(
                color: WizardColors.midnight,
                border: Border(bottom: BorderSide(color: WizardColors.borderSubtle)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: WizardColors.textPrimary),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isDemo
                          ? WizardColors.cyanArcane
                          : (_connected
                              ? WizardColors.emeraldSage
                              : (_connecting
                                  ? WizardColors.goldStarlight
                                  : WizardColors.coralError)),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Omarchy Remote Desktop',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: WizardColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _connected && _fpsEstimate > 0
                              ? '$_statusText • ${_fpsEstimate.toStringAsFixed(1)} fps'
                              : _statusText,
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
                  if (_monitors.length > 1)
                    PopupMenuButton<String>(
                      tooltip: 'Select Monitor',
                      icon: const Icon(Icons.monitor_rounded, color: WizardColors.cyanArcane, size: 20),
                      onSelected: (name) {
                        setState(() => _selectedOutput = name);
                        _sendJson({'type': 'config', 'output': name});
                      },
                      itemBuilder: (_) => _monitors
                          .map(
                            (m) => PopupMenuItem<String>(
                              value: m['name'] as String? ?? '',
                              child: Text('${m['name']} (${m['width']}x${m['height']})'),
                            ),
                          )
                          .toList(),
                    ),
                  IconButton(
                    tooltip: _preset == _StreamPreset.fast ? 'Switch to Crisp' : 'Switch to Fast',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _switchPreset(
                      _preset == _StreamPreset.fast
                          ? _StreamPreset.crisp
                          : _StreamPreset.fast,
                    ),
                    icon: Icon(
                      _preset == _StreamPreset.crisp
                          ? Icons.hd_rounded
                          : Icons.speed_rounded,
                      color: WizardColors.cyanArcane,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reset Zoom',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _transformController.value = Matrix4.identity(),
                    icon: const Icon(Icons.fit_screen_rounded, color: WizardColors.textMuted, size: 20),
                  ),
                  if (!isDemo && !_connected && !_connecting)
                    FilledButton(
                      onPressed: () => unawaited(_connect()),
                      style: FilledButton.styleFrom(
                        backgroundColor: WizardColors.cyanArcane,
                        foregroundColor: WizardColors.obsidian,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Connect', style: TextStyle(fontSize: 12)),
                    )
                  else if (!isDemo)
                    IconButton(
                      tooltip: _paused ? 'Resume Stream' : 'Pause Stream',
                      visualDensity: VisualDensity.compact,
                      onPressed: _togglePause,
                      icon: Icon(
                        _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        color: WizardColors.violetArcane,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),

            // Workspace strip
            Container(
              height: 36,
              color: WizardColors.obsidian,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 8, top: 4),
                    child: Text(
                      'WS',
                      style: TextStyle(
                        color: WizardColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final ws in _workspaces)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${ws['id']}'),
                        selected: _activeWorkspace == (ws['id'] as num?)?.toInt(),
                        visualDensity: VisualDensity.compact,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        onSelected: (_) {
                          final id = (ws['id'] as num?)?.toInt() ?? 1;
                          setState(() => _activeWorkspace = id);
                          _sendJson({'type': 'workspace', 'id': id});
                        },
                      ),
                    ),
                ],
              ),
            ),

            // Main interactive desktop viewport
            Expanded(
              child: Container(
                color: const Color(0xFF07080D),
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1.0,
                  maxScale: 8.0,
                  panEnabled: _touchMode != _TouchMode.drag,
                  scaleEnabled: true,
                  boundaryMargin: const EdgeInsets.all(24),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: LayoutBuilder(
                        builder: (ctx, constraints) {
                          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _onCanvasTapUp(d, canvasSize),
                            onLongPressStart: (d) => _onCanvasLongPress(d, canvasSize),
                            onPanStart: _touchMode == _TouchMode.drag
                                ? (d) {
                                    final n = _normalizeLocal(d.localPosition, canvasSize);
                                    _sendJson({
                                      'type': 'pointer',
                                      'action': 'down',
                                      'button': 'left',
                                      'x': n.dx,
                                      'y': n.dy,
                                    });
                                  }
                                : null,
                            onPanUpdate: _touchMode == _TouchMode.drag
                                ? (d) {
                                    final n = _normalizeLocal(d.localPosition, canvasSize);
                                    _sendJson({
                                      'type': 'pointer',
                                      'action': 'move',
                                      'x': n.dx,
                                      'y': n.dy,
                                    });
                                  }
                                : null,
                            onPanEnd: _touchMode == _TouchMode.drag
                                ? (_) {
                                    _sendJson({
                                      'type': 'pointer',
                                      'action': 'up',
                                      'button': 'left',
                                    });
                                  }
                                : null,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (isDemo)
                                  _DemoHyprlandDesktop(
                                    activeWorkspace: _activeWorkspace,
                                    lastTap: _lastTapNormalized,
                                    toast: _demoToast,
                                  )
                                else if (_latestFrame != null)
                                  Image.memory(
                                    _latestFrame!,
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.medium,
                                  )
                                else
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(color: WizardColors.cyanArcane),
                                        const SizedBox(height: 12),
                                        Text(
                                          _statusText,
                                          style: const TextStyle(color: WizardColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_lastTapNormalized != null)
                                  Positioned(
                                    left: (_lastTapNormalized!.dx * canvasSize.width) - 12,
                                    top: (_lastTapNormalized!.dy * canvasSize.height) - 12,
                                    child: IgnorePointer(
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _touchMode == _TouchMode.rightClick
                                                ? WizardColors.violetArcane
                                                : WizardColors.cyanArcane,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Collapsible keyboard text bar + shortcuts
            if (_showKeyboard)
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                decoration: const BoxDecoration(
                  color: WizardColors.surfaceCard,
                  border: Border(top: BorderSide(color: WizardColors.borderSubtle)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            focusNode: _textFocus,
                            style: const TextStyle(color: WizardColors.textPrimary, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Type text to desktop...',
                              hintStyle: const TextStyle(color: WizardColors.textMuted),
                              isDense: true,
                              filled: true,
                              fillColor: WizardColors.obsidian,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => _sendText(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _sendText,
                          style: FilledButton.styleFrom(
                            backgroundColor: WizardColors.violetArcane,
                            foregroundColor: WizardColors.obsidian,
                          ),
                          child: const Text('Type'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _KeyChip('ENTER', () => _sendSpecialKey('Return')),
                          _KeyChip('ESC', () => _sendSpecialKey('Escape')),
                          _KeyChip('TAB', () => _sendSpecialKey('Tab')),
                          _KeyChip('BKSP', () => _sendSpecialKey('BackSpace')),
                          _KeyChip('SUPER', () => _sendSpecialKey('Super_L')),
                          _KeyChip('CTRL+C', () => _sendSpecialKey('c', modifiers: ['ctrl'])),
                          _KeyChip('CTRL+V', () => _sendSpecialKey('v', modifiers: ['ctrl'])),
                          _KeyChip('ALT+TAB', () => _sendSpecialKey('Tab', modifiers: ['alt'])),
                          _KeyChip('↑', () => _sendSpecialKey('Up')),
                          _KeyChip('↓', () => _sendSpecialKey('Down')),
                          _KeyChip('←', () => _sendSpecialKey('Left')),
                          _KeyChip('→', () => _sendSpecialKey('Right')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom pointer / control dock
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                color: WizardColors.midnight,
                border: Border(top: BorderSide(color: WizardColors.borderSubtle)),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _ModePill(
                    label: 'Click',
                    icon: Icons.touch_app_rounded,
                    selected: _touchMode == _TouchMode.leftClick,
                    onTap: () => setState(() => _touchMode = _TouchMode.leftClick),
                  ),
                  _ModePill(
                    label: 'R-Click',
                    icon: Icons.mouse_rounded,
                    selected: _touchMode == _TouchMode.rightClick,
                    onTap: () => setState(() => _touchMode = _TouchMode.rightClick),
                  ),
                  _ModePill(
                    label: 'Drag',
                    icon: Icons.open_with_rounded,
                    selected: _touchMode == _TouchMode.drag,
                    onTap: () => setState(() => _touchMode = _TouchMode.drag),
                  ),
                  _KeyChip('Scroll ▲', () => _sendJson({'type': 'pointer', 'action': 'scroll', 'dy': -4.0})),
                  _KeyChip('Scroll ▼', () => _sendJson({'type': 'pointer', 'action': 'scroll', 'dy': 4.0})),
                  _ModePill(
                    label: 'Keys',
                    icon: Icons.keyboard_rounded,
                    selected: _showKeyboard,
                    onTap: () {
                      setState(() => _showKeyboard = !_showKeyboard);
                      if (_showKeyboard) _textFocus.requestFocus();
                    },
                  ),
                  _KeyChip('Refresh', () => _sendJson({'type': 'refresh'})),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? WizardColors.cyanArcane : WizardColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected ? WizardColors.obsidian : WizardColors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? WizardColors.obsidian : WizardColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: WizardColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: WizardColors.textPrimary,
                  fontSize: 11,
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

class _DemoHyprlandDesktop extends StatelessWidget {
  const _DemoHyprlandDesktop({
    required this.activeWorkspace,
    this.lastTap,
    this.toast,
  });

  final int activeWorkspace;
  final Offset? lastTap;
  final String? toast;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16192C), Color(0xFF1E223D), Color(0xFF121526)],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // Simulated Waybar
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: WizardColors.obsidian.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WizardColors.borderSubtle),
            ),
            child: Row(
              children: [
                Text(
                  'WS $activeWorkspace',
                  style: const TextStyle(
                    color: WizardColors.cyanArcane,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Omarchy Hyprland • Demo Desktop',
                  style: TextStyle(color: WizardColors.textMuted, fontSize: 10),
                ),
                const Spacer(),
                const Text(
                  '♫ Spotify',
                  style: TextStyle(color: WizardColors.emeraldSage, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: WizardColors.obsidian.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: WizardColors.cyanArcane, width: 1.5),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'kitsune@omarchy — kitty',
                          style: TextStyle(
                            color: WizardColors.cyanArcane,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '~ \$ systemctl --user status omarchy-wizard-bridge\n'
                          '● active (running) :7842\n'
                          '~ \$ Tap anywhere to inject Wayland clicks!\n'
                          'Pinch to zoom • Pair live in Sanctum for real screen.',
                          style: TextStyle(
                            color: WizardColors.textPrimary,
                            fontSize: 10,
                            fontFamily: 'monospace',
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: WizardColors.surfaceCard.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: WizardColors.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Control Preview',
                          style: TextStyle(
                            color: WizardColors.violetArcane,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          lastTap != null
                              ? 'Cursor: ${(lastTap!.dx * 100).round()}%, ${(lastTap!.dy * 100).round()}%'
                              : 'Tap screen to move cursor',
                          style: const TextStyle(
                            color: WizardColors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        if (toast != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            toast!,
                            style: const TextStyle(
                              color: WizardColors.emeraldSage,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
