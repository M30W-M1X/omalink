import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../services/bridge_client.dart';
import '../theme/wizard_theme.dart';

class TrackpadScreen extends StatefulWidget {
  const TrackpadScreen({
    super.key,
    required this.client,
  });

  final BridgeClient client;

  @override
  State<TrackpadScreen> createState() => _TrackpadScreenState();
}

class _TrackpadScreenState extends State<TrackpadScreen> {
  final TextEditingController _textController = TextEditingController();
  WebSocket? _ws;
  StreamSubscription<dynamic>? _wsSub;
  bool _connected = false;
  bool _presentationMode = false;
  bool _showKeyboard = false;
  double _sensitivity = 1.8;
  String _statusText = 'Connecting...';
  int _activePointers = 0;

  @override
  void initState() {
    super.initState();
    if (widget.client.settings.demoMode) {
      _statusText = 'Demo Wireless Trackpad';
    } else {
      unawaited(_connect());
    }
  }

  Future<void> _connect() async {
    final settings = widget.client.settings;
    final uri = Uri.parse(settings.desktopWsUrl).replace(queryParameters: {
      'paused': '1',
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
        (_) {},
        onDone: () {
          if (mounted) {
            setState(() {
              _connected = false;
              _statusText = 'Disconnected';
            });
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() {
              _connected = false;
              _statusText = 'Connection error';
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _connected = true;
          _statusText = 'Live 120Hz Wayland Pointer';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connected = false;
          _statusText = 'Failed: $e';
        });
      }
    }
  }

  void _send(Map<String, dynamic> payload) {
    if (widget.client.settings.demoMode) {
      setState(() => _statusText = 'Demo: ${payload['action'] ?? payload['key'] ?? payload['text']}');
      return;
    }
    final ws = _ws;
    if (ws != null && _connected) {
      try {
        ws.add(jsonEncode(payload));
      } catch (_) {}
    }
  }

  void _sendKey(String key, {List<String>? modifiers}) {
    _send({
      'type': 'key',
      'key': key,
      if (modifiers != null && modifiers.isNotEmpty) 'modifiers': modifiers,
    });
  }

  @override
  void dispose() {
    unawaited(_wsSub?.cancel());
    unawaited(_ws?.close());
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WizardColors.obsidian,
      appBar: AppBar(
        backgroundColor: WizardColors.midnight,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _presentationMode ? 'Presentation Remote' : 'Wireless Trackpad',
              style: TextStyle(
                color: WizardColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              _statusText,
              style: TextStyle(color: WizardColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _presentationMode ? 'Trackpad Mode' : 'Presentation Mode',
            onPressed: () => setState(() => _presentationMode = !_presentationMode),
            icon: Icon(
              _presentationMode ? Icons.touch_app_rounded : Icons.slideshow_rounded,
              color: WizardColors.cyanArcane,
            ),
          ),
          IconButton(
            tooltip: 'Keyboard',
            onPressed: () => setState(() => _showKeyboard = !_showKeyboard),
            icon: Icon(
              Icons.keyboard_rounded,
              color: _showKeyboard ? WizardColors.violetArcane : WizardColors.textMuted,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_presentationMode)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Expanded(
                              child: _SlideButton(
                                icon: Icons.arrow_back_rounded,
                                label: 'PREV SLIDE',
                                color: WizardColors.surfaceCard,
                                textColor: WizardColors.textPrimary,
                                onTap: () => _sendKey('Left'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: _SlideButton(
                                icon: Icons.arrow_forward_rounded,
                                label: 'NEXT SLIDE',
                                color: WizardColors.violetArcane,
                                textColor: WizardColors.obsidian,
                                onTap: () => _sendKey('Right'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _sendKey('F5'),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Start (F5)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _sendKey('b'),
                              icon: const Icon(Icons.visibility_off_outlined),
                              label: const Text('Blackout (B)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _sendKey('Escape'),
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('ESC'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Listener(
                          onPointerDown: (_) => _activePointers++,
                          onPointerUp: (_) => _activePointers = (_activePointers - 1).clamp(0, 10),
                          onPointerCancel: (_) => _activePointers = 0,
                          child: GestureDetector(
                            onTap: () => _send({'type': 'pointer', 'action': 'tap', 'button': 'left'}),
                            onDoubleTap: () =>
                                _send({'type': 'pointer', 'action': 'double_tap', 'button': 'left'}),
                            onLongPress: () =>
                                _send({'type': 'pointer', 'action': 'right_click'}),
                            onScaleUpdate: (details) {
                              final d = details.focalPointDelta;
                              if (d.distance < 0.2) return;
                              if (_activePointers >= 2) {
                                _send({
                                  'type': 'pointer',
                                  'action': 'scroll',
                                  'dx': -d.dx * 0.25,
                                  'dy': -d.dy * 0.25,
                                });
                              } else {
                                _send({
                                  'type': 'pointer',
                                  'action': 'relative',
                                  'dx': d.dx * _sensitivity,
                                  'dy': d.dy * _sensitivity,
                                });
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: WizardColors.surfaceCard,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: WizardColors.borderSubtle),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.touch_app_outlined,
                                      size: 42,
                                      color: WizardColors.textMuted.withValues(alpha: 0.45),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '1 Finger: Move & Tap\n2 Fingers: Scroll • Long-Press: Right Click',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: WizardColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Dedicated scroll rail
                      GestureDetector(
                        onVerticalDragUpdate: (d) {
                          _send({
                            'type': 'pointer',
                            'action': 'scroll',
                            'dy': d.delta.dy * 0.35,
                          });
                        },
                        child: Container(
                          width: 40,
                          decoration: BoxDecoration(
                            color: WizardColors.midnight,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: WizardColors.borderSubtle),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Icon(Icons.keyboard_arrow_up, color: WizardColors.textMuted),
                              ),
                              RotatedBox(
                                quarterTurns: 3,
                                child: Text(
                                  'SCROLL',
                                  style: TextStyle(
                                    color: WizardColors.textMuted,
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Icon(Icons.keyboard_arrow_down, color: WizardColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_showKeyboard)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                color: WizardColors.surfaceCard,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: TextStyle(color: WizardColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Type text to Omarchy...',
                          isDense: true,
                          fillColor: WizardColors.obsidian,
                        ),
                        onSubmitted: (_) {
                          if (_textController.text.isNotEmpty) {
                            _send({'type': 'key', 'text': _textController.text});
                            _textController.clear();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        if (_textController.text.isNotEmpty) {
                          _send({'type': 'key', 'text': _textController.text});
                          _textController.clear();
                        }
                      },
                      child: const Text('Type'),
                    ),
                  ],
                ),
              ),

            if (!_presentationMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('Speed', style: TextStyle(color: WizardColors.textMuted, fontSize: 11)),
                        Expanded(
                          child: Slider(
                            value: _sensitivity,
                            min: 0.8,
                            max: 3.5,
                            onChanged: (v) => setState(() => _sensitivity = v),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => _send({'type': 'pointer', 'action': 'tap', 'button': 'left'}),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                            child: const Text('Left Click'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => _send({'type': 'pointer', 'action': 'tap', 'button': 'middle'}),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                            child: const Text('Middle'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => _send({'type': 'pointer', 'action': 'right_click'}),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                            child: const Text('Right Click'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlideButton extends StatelessWidget {
  const _SlideButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: textColor),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
