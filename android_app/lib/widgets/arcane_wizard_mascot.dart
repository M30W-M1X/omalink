import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models/wizard_avatar.dart';
import '../models/wizard_mood.dart';
import '../theme/wizard_theme.dart';

class ArcaneWizardMascot extends StatefulWidget {
  const ArcaneWizardMascot({
    super.key,
    required this.mood,
    required this.quip,
    this.avatarStyle = WizardAvatarStyle.classic,
    this.onTap,
    this.onLongPress,
    this.size = 210,
  });

  final WizardMood mood;
  final String quip;
  final WizardAvatarStyle avatarStyle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double size;

  @override
  State<ArcaneWizardMascot> createState() => _ArcaneWizardMascotState();
}

class _ArcaneWizardMascotState extends State<ArcaneWizardMascot>
    with TickerProviderStateMixin {
  late final AnimationController _floatController;
  late final AnimationController _orbitController;
  late final AnimationController _blinkController;
  late final AnimationController _burstController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didUpdateWidget(covariant ArcaneWizardMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mood != oldWidget.mood) {
      if (widget.mood == WizardMood.celebrating) {
        _burstController.forward(from: 0);
      }
      _orbitController.duration = widget.mood == WizardMood.casting
          ? const Duration(milliseconds: 1600)
          : const Duration(milliseconds: 4200);
      if (!_orbitController.isAnimating) {
        _orbitController.repeat();
      } else {
        _orbitController.repeat();
      }
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _orbitController.dispose();
    _blinkController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _burstController.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentForMood(widget.mood);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _handleTap,
          onLongPress: widget.onLongPress,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _floatController,
                _orbitController,
                _blinkController,
                _burstController,
              ]),
              builder: (context, _) {
                final assetPath = widget.avatarStyle.assetPath;
                if (assetPath == null) {
                  return CustomPaint(
                    painter: _WizardPainter(
                      mood: widget.mood,
                      floatPhase: _floatController.value,
                      orbitPhase: _orbitController.value,
                      blinkPhase: _blinkController.value,
                      burstPhase: _burstController.value,
                      accent: accent,
                    ),
                  );
                }
                return _buildAnimatedIllustratedAvatar(
                  assetPath: assetPath,
                  accent: accent,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Container(
            key: ValueKey<String>('${widget.mood.name}:${widget.quip}'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: WizardColors.surfaceElevated.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accent.withValues(alpha: 0.45),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.quip,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: WizardColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedIllustratedAvatar({
    required String assetPath,
    required Color accent,
  }) {
    final floatAngle = _floatController.value * 2 * math.pi;
    final orbitAngle = _orbitController.value * 2 * math.pi;
    final burst = _burstController.value;
    final burstArc = burst > 0 && burst < 1 ? math.sin(burst * math.pi) : 0.0;

    final isCasting = widget.mood == WizardMood.casting;
    final isCelebrating = widget.mood == WizardMood.celebrating;
    final isError = widget.mood == WizardMood.error;

    // Organic floating bob + boop spring hop
    final bobAmp = isCasting ? 6.5 : (isCelebrating ? 8.0 : 4.5);
    final dy = math.sin(floatAngle) * bobAmp - burstArc * 14.0;
    final dx = isError ? math.sin(orbitAngle * 6) * 3.2 : 0.0;

    // Expressive tilt & living squash-and-stretch breathing
    final tilt = isCelebrating
        ? math.sin(floatAngle * 2) * 0.075
        : (isCasting
            ? math.sin(orbitAngle) * 0.055
            : math.sin(floatAngle) * 0.032) +
            burstArc * math.sin(burst * math.pi * 3) * 0.08;
    final breath = math.sin(floatAngle) * (isCasting ? 0.028 : 0.018);
    final scaleX = 1.0 - breath + burstArc * 0.075;
    final scaleY = 1.0 + breath + burstArc * 0.045;

    final portraitSize = widget.size * 0.74;
    final shimmerPos = (_orbitController.value * 2.2) - 0.6;

    return Stack(
      alignment: Alignment.center,
      children: [
        // 1. Back glowing arcane halo & rotating rune ring
        Positioned.fill(
          child: CustomPaint(
            painter: _AvatarAuraBackPainter(
              mood: widget.mood,
              floatPhase: _floatController.value,
              orbitPhase: _orbitController.value,
              burstPhase: burst,
              accent: accent,
            ),
          ),
        ),
        // 2. Living floating/breathing/tilting portrait medallion
        Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: tilt,
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: scaleY,
              child: Container(
                width: portraitSize,
                height: portraitSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: isCasting ? 0.45 : 0.28),
                      blurRadius: isCasting ? 26 : 18,
                      spreadRadius: isCasting ? 2 : 0,
                    ),
                  ],
                  border: Border.all(
                    color: accent.withValues(alpha: 0.65 + burstArc * 0.35),
                    width: 2.4,
                  ),
                ),
                child: ClipOval(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        assetPath,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                      // Animated diagonal magic sheen sweep
                      if (isCasting || isCelebrating || burstArc > 0.02)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment(shimmerPos - 0.6, -1.0),
                                end: Alignment(shimmerPos + 0.6, 1.0),
                                colors: [
                                  Colors.transparent,
                                  accent.withValues(alpha: isCasting ? 0.22 : 0.16),
                                  Colors.white.withValues(alpha: 0.16),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.45, 0.52, 1.0],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // 3. Foreground orbiting starlight sparkles, rising mana & boop burst FX
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _AvatarFxFrontPainter(
                mood: widget.mood,
                floatPhase: _floatController.value,
                orbitPhase: _orbitController.value,
                blinkPhase: _blinkController.value,
                burstPhase: burst,
                accent: accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _accentForMood(WizardMood mood) {
    switch (mood) {
      case WizardMood.idle:
        return WizardColors.cyanArcane;
      case WizardMood.listening:
        return WizardColors.goldStarlight;
      case WizardMood.casting:
        return WizardColors.violetArcane;
      case WizardMood.awaitingApproval:
        return WizardColors.goldStarlight;
      case WizardMood.celebrating:
        return WizardColors.emeraldSage;
      case WizardMood.error:
        return WizardColors.coralError;
    }
  }
}

class _WizardPainter extends CustomPainter {
  _WizardPainter({
    required this.mood,
    required this.floatPhase,
    required this.orbitPhase,
    required this.blinkPhase,
    required this.burstPhase,
    required this.accent,
  });

  final WizardMood mood;
  final double floatPhase;
  final double orbitPhase;
  final double blinkPhase;
  final double burstPhase;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.52;

    final floatAngle = floatPhase * 2 * math.pi;
    final bobAmp = mood == WizardMood.casting ? h * 0.036 : h * 0.025;
    final hopOffset = mood == WizardMood.celebrating
        ? -math.sin(burstPhase * math.pi).clamp(0.0, 1.0) * h * 0.07
        : 0.0;
    final bobY = math.sin(floatAngle) * bobAmp + hopOffset;
    final tilt = mood == WizardMood.error
        ? 0.08 * math.sin(floatAngle * 2)
        : 0.03 * math.cos(floatAngle);

    // 1. Soft cosmic aura behind wizard
    final auraRadius = w * (mood == WizardMood.casting ? 0.44 : 0.36);
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: mood == WizardMood.casting ? 0.34 : 0.2),
          WizardColors.violetArcane.withValues(alpha: 0.07),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy + bobY * 0.4), radius: auraRadius));
    canvas.drawCircle(Offset(cx, cy + bobY * 0.4), auraRadius, auraPaint);

    // 2. Orbiting arcane rune ring
    _drawArcaneRing(canvas, Offset(cx, cy + h * 0.04 + bobY * 0.3), w);

    // 3. Ground levitation shadow
    final shadowScale = 1.0 - (bobY / (h * 0.09)).clamp(-0.2, 0.25);
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.89),
        width: w * 0.36 * shadowScale,
        height: h * 0.065 * shadowScale,
      ),
      shadowPaint,
    );

    // 4. Main floating wizard body
    canvas.save();
    canvas.translate(cx, cy + bobY);
    canvas.rotate(tilt);

    _drawCloak(canvas, w, h, floatAngle);
    _drawFace(canvas, w, h);
    _drawHat(canvas, w, h, floatAngle);
    _drawLeftSpellbookHand(canvas, w, h, floatAngle);
    _drawRightStaffHand(canvas, w, h, floatAngle);

    canvas.restore();

    // 5. Rising magical particles when casting, or celebratory burst
    _drawParticles(canvas, cx, cy + bobY, w, h);
  }

  void _drawArcaneRing(Canvas canvas, Offset center, double w) {
    final ringRadius = w * (mood == WizardMood.casting ? 0.40 : 0.34);
    final ringAlpha = mood == WizardMood.casting ? 0.65 : 0.24;
    final ringPaint = Paint()
      ..color = accent.withValues(alpha: ringAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = mood == WizardMood.casting ? 2.0 : 1.2;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1.0, 0.42);
    canvas.rotate(orbitPhase * 2 * math.pi);

    // Dashed arcane circle
    const segments = 16;
    for (int i = 0; i < segments; i++) {
      final start = (i * 2 * math.pi / segments);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: ringRadius),
        start,
        (2 * math.pi / segments) * 0.55,
        false,
        ringPaint,
      );
    }

    // 4 orbiting rune diamonds
    final dotPaint = Paint()..color = accent.withValues(alpha: ringAlpha + 0.2);
    for (int i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final p = Offset(math.cos(a) * ringRadius, math.sin(a) * ringRadius);
      canvas.drawCircle(p, mood == WizardMood.casting ? 3.5 : 2.3, dotPaint);
    }
    canvas.restore();
  }

  void _drawCloak(Canvas canvas, double w, double h, double floatAngle) {
    final sway = math.sin(floatAngle + 0.8) * w * 0.015;
    final cloakPath = Path()
      ..moveTo(-w * 0.14, -h * 0.02)
      ..quadraticBezierTo(-w * 0.24, h * 0.14, -w * 0.22 + sway, h * 0.27)
      ..quadraticBezierTo(-w * 0.11, h * 0.31, 0 + sway * 0.5, h * 0.29)
      ..quadraticBezierTo(w * 0.11, h * 0.31, w * 0.22 + sway, h * 0.27)
      ..quadraticBezierTo(w * 0.24, h * 0.14, w * 0.14, -h * 0.02)
      ..close();

    final cloakPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF28315A), Color(0xFF171C36)],
      ).createShader(Rect.fromLTWH(-w * 0.24, -h * 0.02, w * 0.48, h * 0.34));
    canvas.drawPath(cloakPath, cloakPaint);

    // Glowing arcane cloak collar + central sash
    final trimPaint = Paint()
      ..color = accent.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final collarPath = Path()
      ..moveTo(-w * 0.12, 0)
      ..quadraticBezierTo(0, h * 0.06, w * 0.12, 0);
    canvas.drawPath(collarPath, trimPaint);

    // Cute glowing clasp gem at the collar
    canvas.drawCircle(
      Offset(0, h * 0.032),
      w * 0.022,
      Paint()..color = WizardColors.goldStarlight,
    );
  }

  void _drawFace(Canvas canvas, double w, double h) {
    // Cozy round hooded shadow head
    final headCenter = Offset(0, -h * 0.075);
    final headRadius = w * 0.145;

    // Subtle hood rim
    canvas.drawCircle(
      headCenter,
      headRadius + 3.5,
      Paint()..color = const Color(0xFF2B3460),
    );
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()..color = const Color(0xFF0A0D18),
    );

    // Cute rosy cheeks
    final cheekPaint = Paint()
      ..color = WizardColors.violetArcane.withValues(alpha: 0.38);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-w * 0.075, headCenter.dy + h * 0.028),
        width: w * 0.042,
        height: h * 0.02,
      ),
      cheekPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.075, headCenter.dy + h * 0.028),
        width: w * 0.042,
        height: h * 0.02,
      ),
      cheekPaint,
    );

    final leftEye = Offset(-w * 0.052, headCenter.dy - h * 0.004);
    final rightEye = Offset(w * 0.052, headCenter.dy - h * 0.004);

    if (mood == WizardMood.celebrating) {
      // Cute happy ^ ^ eyes
      final happyPaint = Paint()
        ..color = WizardColors.emeraldSage
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round;
      for (final eye in [leftEye, rightEye]) {
        final arc = Path()
          ..moveTo(eye.dx - w * 0.025, eye.dy + h * 0.008)
          ..quadraticBezierTo(eye.dx, eye.dy - h * 0.018, eye.dx + w * 0.025, eye.dy + h * 0.008);
        canvas.drawPath(arc, happyPaint);
      }
      // Cute tiny smile
      final smile = Path()
        ..moveTo(-w * 0.022, headCenter.dy + h * 0.028)
        ..quadraticBezierTo(0, headCenter.dy + h * 0.045, w * 0.022, headCenter.dy + h * 0.028);
      canvas.drawPath(
        smile,
        Paint()
          ..color = WizardColors.goldStarlight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    if (mood == WizardMood.error) {
      // Cute X X dizzy eyes
      final errPaint = Paint()
        ..color = WizardColors.coralError
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      final r = w * 0.02;
      for (final eye in [leftEye, rightEye]) {
        canvas.drawLine(eye + Offset(-r, -r), eye + Offset(r, r), errPaint);
        canvas.drawLine(eye + Offset(r, -r), eye + Offset(-r, r), errPaint);
      }
      return;
    }

    // Blink factor (quick blink near end of 3.6s cycle)
    final isBlinking = blinkPhase > 0.93;
    final eyeColor = mood == WizardMood.casting
        ? WizardColors.violetArcane
        : (mood == WizardMood.awaitingApproval
            ? WizardColors.goldStarlight
            : WizardColors.cyanArcane);

    if (isBlinking) {
      final blinkPaint = Paint()
        ..color = eyeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final eye in [leftEye, rightEye]) {
        canvas.drawLine(
          Offset(eye.dx - w * 0.024, eye.dy),
          Offset(eye.dx + w * 0.024, eye.dy),
          blinkPaint,
        );
      }
    } else {
      final eyeGlow = Paint()
        ..color = eyeColor.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      final eyeFill = Paint()..color = eyeColor;
      final catchlight = Paint()..color = Colors.white;
      final eyeW = w * 0.036;
      final eyeH = h * (mood == WizardMood.listening ? 0.044 : 0.038);

      for (final eye in [leftEye, rightEye]) {
        final rect = Rect.fromCenter(center: eye, width: eyeW, height: eyeH);
        canvas.drawOval(rect.inflate(2), eyeGlow);
        canvas.drawOval(rect, eyeFill);
        canvas.drawCircle(
          Offset(eye.dx - eyeW * 0.18, eye.dy - eyeH * 0.2),
          w * 0.008,
          catchlight,
        );
      }
    }
  }

  void _drawHat(Canvas canvas, double w, double h, double floatAngle) {
    final tipSway = math.sin(floatAngle * 1.2) * w * 0.022;

    // Brim of the hat
    final brimRect = Rect.fromCenter(
      center: Offset(0, -h * 0.17),
      width: w * 0.46,
      height: h * 0.095,
    );
    canvas.drawOval(
      brimRect,
      Paint()..color = const Color(0xFF1F2749),
    );
    canvas.drawOval(
      brimRect,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Tall slouchy pointed wizard cone
    final tip = Offset(w * 0.13 + tipSway, -h * 0.40);
    final conePath = Path()
      ..moveTo(-w * 0.155, -h * 0.17)
      ..quadraticBezierTo(-w * 0.11, -h * 0.34, tip.dx, tip.dy)
      ..quadraticBezierTo(w * 0.09, -h * 0.29, w * 0.155, -h * 0.17)
      ..close();

    final conePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF333E73), Color(0xFF191F3D)],
      ).createShader(Rect.fromLTWH(-w * 0.16, -h * 0.41, w * 0.34, h * 0.25));
    canvas.drawPath(conePath, conePaint);

    // Glowing rune band around the hat
    final bandPath = Path()
      ..moveTo(-w * 0.145, -h * 0.185)
      ..quadraticBezierTo(0, -h * 0.15, w * 0.145, -h * 0.185)
      ..lineTo(w * 0.138, -h * 0.215)
      ..quadraticBezierTo(0, -h * 0.18, -w * 0.138, -h * 0.215)
      ..close();
    canvas.drawPath(
      bandPath,
      Paint()..color = accent.withValues(alpha: 0.82),
    );

    // Dangling golden star charm hanging from bent hat tip
    final charmStart = tip;
    final charmEnd = Offset(tip.dx + tipSway * 0.4, tip.dy + h * 0.065);
    canvas.drawLine(
      charmStart,
      charmEnd,
      Paint()
        ..color = WizardColors.goldStarlight.withValues(alpha: 0.75)
        ..strokeWidth = 1.5,
    );
    _drawFourPointStar(
      canvas,
      charmEnd,
      w * 0.032,
      WizardColors.goldStarlight,
    );
  }

  void _drawLeftSpellbookHand(
    Canvas canvas,
    double w,
    double h,
    double floatAngle,
  ) {
    final handPos = Offset(-w * 0.23, h * 0.08 + math.sin(floatAngle + 1.2) * h * 0.015);
    // Cute mitten hand
    canvas.drawCircle(
      handPos,
      w * 0.038,
      Paint()..color = const Color(0xFF2B3460),
    );

    // Tiny hovering open spellbook above left hand
    final bookCenter = Offset(handPos.dx - w * 0.02, handPos.dy - h * 0.07);
    canvas.save();
    canvas.translate(bookCenter.dx, bookCenter.dy);
    canvas.rotate(-0.18 + math.sin(floatAngle) * 0.06);

    final leftPage = RRect.fromRectAndRadius(
      Rect.fromLTWH(-w * 0.065, -h * 0.035, w * 0.062, h * 0.07),
      const Radius.circular(3),
    );
    final rightPage = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.003, -h * 0.035, w * 0.062, h * 0.07),
      const Radius.circular(3),
    );
    final pageColor = mood == WizardMood.casting
        ? WizardColors.cyanArcane.withValues(alpha: 0.92)
        : WizardColors.textPrimary.withValues(alpha: 0.88);
    canvas.drawRRect(leftPage, Paint()..color = pageColor);
    canvas.drawRRect(rightPage, Paint()..color = pageColor);

    // Book spine
    canvas.drawLine(
      Offset(0, -h * 0.035),
      Offset(0, h * 0.035),
      Paint()
        ..color = WizardColors.violetArcane
        ..strokeWidth = 2.0,
    );
    canvas.restore();
  }

  void _drawRightStaffHand(
    Canvas canvas,
    double w,
    double h,
    double floatAngle,
  ) {
    final handPos = Offset(w * 0.23, h * 0.07 + math.cos(floatAngle) * h * 0.015);

    // Staff shaft
    final staffBottom = Offset(handPos.dx - w * 0.02, h * 0.26);
    final staffTop = Offset(handPos.dx + w * 0.045, -h * 0.14);
    canvas.drawLine(
      staffBottom,
      staffTop,
      Paint()
        ..color = const Color(0xFF8E6B4F)
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round,
    );

    // Glowing crystal orb on staff tip
    final pulse = 1.0 + 0.16 * math.sin(orbitPhase * 4 * math.pi);
    final orbRadius = w * 0.042 * (mood == WizardMood.casting ? pulse : 1.0);
    canvas.drawCircle(
      staffTop,
      orbRadius * 1.9,
      Paint()
        ..color = accent.withValues(alpha: mood == WizardMood.casting ? 0.55 : 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(
      staffTop,
      orbRadius,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(staffTop.dx - orbRadius * 0.28, staffTop.dy - orbRadius * 0.28),
      orbRadius * 0.32,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // Cute mitten hand gripping staff
    canvas.drawCircle(
      handPos,
      w * 0.038,
      Paint()..color = const Color(0xFF2B3460),
    );
  }

  void _drawParticles(
    Canvas canvas,
    double cx,
    double cy,
    double w,
    double h,
  ) {
    // Ambient floating stars when casting
    if (mood == WizardMood.casting) {
      for (int i = 0; i < 6; i++) {
        final t = (orbitPhase + i / 6) % 1.0;
        final x = cx + math.sin(t * 2 * math.pi + i) * w * 0.32;
        final y = cy + h * 0.22 - t * h * 0.55;
        final alpha = math.sin(t * math.pi).clamp(0.0, 1.0);
        final color = i.isEven ? WizardColors.cyanArcane : WizardColors.violetArcane;
        _drawFourPointStar(
          canvas,
          Offset(x, y),
          w * 0.022,
          color.withValues(alpha: alpha),
        );
      }
    }

    // Celebratory / tap sparkle burst
    if (burstPhase > 0 && burstPhase < 1.0) {
      final fade = (1.0 - burstPhase).clamp(0.0, 1.0);
      for (int i = 0; i < 12; i++) {
        final angle = (i / 12) * 2 * math.pi + 0.2;
        final dist = burstPhase * w * 0.44;
        final pos = Offset(
          cx + math.cos(angle) * dist,
          cy - h * 0.05 + math.sin(angle) * dist,
        );
        final colors = [
          WizardColors.emeraldSage,
          WizardColors.goldStarlight,
          WizardColors.cyanArcane,
          WizardColors.violetArcane,
        ];
        _drawFourPointStar(
          canvas,
          pos,
          w * 0.025 * fade + 1.5,
          colors[i % colors.length].withValues(alpha: fade),
        );
      }
    }
  }

  void _drawFourPointStar(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
  ) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx - radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - radius)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WizardPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.floatPhase != floatPhase ||
        oldDelegate.orbitPhase != orbitPhase ||
        oldDelegate.blinkPhase != blinkPhase ||
        oldDelegate.burstPhase != burstPhase ||
        oldDelegate.accent != accent;
  }
}

class _AvatarAuraBackPainter extends CustomPainter {
  _AvatarAuraBackPainter({
    required this.mood,
    required this.floatPhase,
    required this.orbitPhase,
    required this.burstPhase,
    required this.accent,
  });

  final WizardMood mood;
  final double floatPhase;
  final double orbitPhase;
  final double burstPhase;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * 0.43;
    final pulse = 0.5 + 0.5 * math.sin(floatPhase * 2 * math.pi);
    final burst = burstPhase > 0 && burstPhase < 1 ? math.sin(burstPhase * math.pi) : 0.0;

    // 1. Soft breathing radial glow behind the avatar medallion
    final glowR = baseR * (1.06 + pulse * 0.07 + burst * 0.14);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: mood == WizardMood.casting ? 0.34 : 0.22),
          WizardColors.violetArcane.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.35, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowR));
    canvas.drawCircle(center, glowR, haloPaint);

    // 2. Rotating segmented arcane magic ring
    final ringR = baseR * (0.98 + pulse * 0.02);
    final ringPaint = Paint()
      ..color = accent.withValues(alpha: mood == WizardMood.casting ? 0.62 : 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = mood == WizardMood.casting ? 2.0 : 1.4
      ..strokeCap = StrokeCap.round;

    final baseAngle = orbitPhase * 2 * math.pi;
    const segments = 6;
    for (int i = 0; i < segments; i++) {
      final start = baseAngle + (i * 2 * math.pi / segments);
      const sweep = math.pi / 7;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringR),
        start,
        sweep,
        false,
        ringPaint,
      );
    }

    // 3. Counter-rotating thin outer orbital track
    final outerR = baseR * 1.07;
    final outerPaint = Paint()
      ..color = WizardColors.goldStarlight.withValues(alpha: 0.22 + pulse * 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (int i = 0; i < 3; i++) {
      final start = -baseAngle * 0.7 + (i * 2 * math.pi / 3);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerR),
        start,
        math.pi / 5,
        false,
        outerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarAuraBackPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.floatPhase != floatPhase ||
        oldDelegate.orbitPhase != orbitPhase ||
        oldDelegate.burstPhase != burstPhase ||
        oldDelegate.accent != accent;
  }
}

class _AvatarFxFrontPainter extends CustomPainter {
  _AvatarFxFrontPainter({
    required this.mood,
    required this.floatPhase,
    required this.orbitPhase,
    required this.blinkPhase,
    required this.burstPhase,
    required this.accent,
  });

  final WizardMood mood;
  final double floatPhase;
  final double orbitPhase;
  final double blinkPhase;
  final double burstPhase;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.44;
    final isCasting = mood == WizardMood.casting;
    final isCelebrating = mood == WizardMood.celebrating;

    // 1. Orbiting starlight sparkles around the portrait edge
    final count = isCasting ? 7 : 5;
    for (int i = 0; i < count; i++) {
      final speed = isCasting ? 2.0 : 1.0;
      final theta = orbitPhase * 2 * math.pi * speed + (i * 2 * math.pi / count);
      final wobble = math.sin(floatPhase * 2 * math.pi + i * 1.3) * 5.0;
      final px = center.dx + math.cos(theta) * (r + wobble);
      final py = center.dy + math.sin(theta) * (r * 0.92 + wobble);
      final twinkle = 0.45 + 0.55 * math.sin(blinkPhase * 2 * math.pi * 2 + i * 1.7).abs();
      final starColor = i.isEven ? accent : WizardColors.goldStarlight;
      _drawStar(
        canvas,
        Offset(px, py),
        (isCasting ? 6.5 : 5.0) * twinkle,
        starColor.withValues(alpha: 0.9 * twinkle),
      );
    }

    // 2. Rising mana motes during casting / celebrating
    if (isCasting || isCelebrating) {
      for (int i = 0; i < 6; i++) {
        final progress = (orbitPhase + i / 6.0) % 1.0;
        final xSpread = math.sin(i * 2.1 + floatPhase * math.pi) * (size.width * 0.34);
        final yPos = center.dy + size.height * 0.32 - progress * (size.height * 0.68);
        final fade = math.sin(progress * math.pi);
        canvas.drawCircle(
          Offset(center.dx + xSpread, yPos),
          2.6 * fade + 1.0,
          Paint()..color = (i.isEven ? accent : WizardColors.goldStarlight).withValues(alpha: 0.75 * fade),
        );
      }
    }

    // 3. Boop / celebration burst ring + radiating stars
    if (burstPhase > 0 && burstPhase < 1) {
      final fade = (1.0 - burstPhase).clamp(0.0, 1.0);
      final burstR = size.width * (0.36 + burstPhase * 0.16);
      canvas.drawCircle(
        center,
        burstR,
        Paint()
          ..color = accent.withValues(alpha: 0.55 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * fade,
      );
      for (int i = 0; i < 8; i++) {
        final angle = i * (math.pi / 4) + burstPhase * 0.5;
        final starPos = Offset(
          center.dx + math.cos(angle) * (burstR + 4),
          center.dy + math.sin(angle) * (burstR + 4),
        );
        _drawStar(
          canvas,
          starPos,
          7.0 * fade,
          (i.isEven ? WizardColors.goldStarlight : accent).withValues(alpha: fade),
        );
      }
    }
  }

  void _drawStar(Canvas canvas, Offset c, double radius, Color color) {
    if (radius <= 0.4) return;
    final path = Path()
      ..moveTo(c.dx, c.dy - radius)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + radius, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + radius)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - radius, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - radius)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AvatarFxFrontPainter oldDelegate) {
    return oldDelegate.mood != mood ||
        oldDelegate.floatPhase != floatPhase ||
        oldDelegate.orbitPhase != orbitPhase ||
        oldDelegate.blinkPhase != blinkPhase ||
        oldDelegate.burstPhase != burstPhase ||
        oldDelegate.accent != accent;
  }
}

/// Compact circular preview thumbnail for any [WizardAvatarStyle].
class WizardAvatarThumbnail extends StatelessWidget {
  const WizardAvatarThumbnail({
    super.key,
    required this.style,
    this.size = 56,
  });

  final WizardAvatarStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = style.assetPath;
    if (asset != null) {
      return ClipOval(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: WizardColors.midnight,
      ),
      child: ClipOval(
        child: CustomPaint(
          size: Size.square(size),
          painter: _WizardPainter(
            mood: WizardMood.idle,
            floatPhase: 0.25,
            orbitPhase: 0.2,
            blinkPhase: 0.1,
            burstPhase: 0,
            accent: WizardColors.cyanArcane,
          ),
        ),
      ),
    );
  }
}
