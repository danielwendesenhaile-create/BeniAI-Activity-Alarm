import 'package:flutter/material.dart';

import '../../../models/activity_model.dart';

/// A simple, fully code-drawn looping stick-figure animation demonstrating
/// the motion for [activityType] - no video/image assets needed. Shown on
/// the pre-activity guide screen so the user knows exactly what movement
/// is expected before the camera starts tracking.
class ActivityStickFigure extends StatefulWidget {
  const ActivityStickFigure({super.key, required this.activityType});

  final ActivityType activityType;

  @override
  State<ActivityStickFigure> createState() => _ActivityStickFigureState();
}

class _ActivityStickFigureState extends State<ActivityStickFigure>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: const Size(220, 220),
        painter: _StickFigurePainter(
          activityType: widget.activityType,
          t: _controller.value,
          color: color,
        ),
      ),
    );
  }
}

/// A drawable pose: a head position plus a list of limb line segments.
class _Figure {
  const _Figure({required this.head, required this.bones});

  final Offset head;
  final List<(Offset, Offset)> bones;
}

class _StickFigurePainter extends CustomPainter {
  _StickFigurePainter({required this.activityType, required this.t, required this.color});

  /// Animated position in the loop, oscillating 0..1..0 (e.g. standing to
  /// squatting and back, arms extended to bent and back).
  final double t;
  final ActivityType activityType;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final limbPaint = Paint()
      ..color = color
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final headPaint = Paint()..color = color;

    final figure = switch (activityType) {
      ActivityType.squats => _squat(size, t),
      ActivityType.pushUps => _pushUp(size, t),
      ActivityType.jumpingJacks => _jumpingJack(size, t),
      ActivityType.neckStretch => _neckStretch(size, t),
    };

    for (final bone in figure.bones) {
      canvas.drawLine(bone.$1, bone.$2, limbPaint);
    }
    canvas.drawCircle(figure.head, 16, headPaint);
  }

  @override
  bool shouldRepaint(covariant _StickFigurePainter oldDelegate) => oldDelegate.t != t;

  _Figure _squat(Size size, double t) {
    final cx = size.width / 2;
    final hipY = size.height * 0.42 + t * size.height * 0.2;
    final headY = hipY - size.height * 0.3;
    final shoulderY = hipY - size.height * 0.2;
    final kneeY = hipY + size.height * 0.16;
    const footY = 0.88;
    final spread = 16 + t * 8;

    final shoulder = Offset(cx, shoulderY);
    final hip = Offset(cx, hipY);
    final kneeL = Offset(cx - spread, kneeY);
    final kneeR = Offset(cx + spread, kneeY);
    final footL = Offset(cx - 18, size.height * footY);
    final footR = Offset(cx + 18, size.height * footY);
    final handL = Offset(cx - 34, shoulderY - 6);
    final handR = Offset(cx + 34, shoulderY - 6);

    return _Figure(
      head: Offset(cx, headY),
      bones: [
        (shoulder, hip),
        (shoulder, handL),
        (shoulder, handR),
        (hip, kneeL),
        (kneeL, footL),
        (hip, kneeR),
        (kneeR, footR),
      ],
    );
  }

  _Figure _pushUp(Size size, double t) {
    final baseY = size.height * 0.55;
    final dip = t * size.height * 0.12;
    final left = size.width * 0.18;
    final right = size.width * 0.78;

    final foot = Offset(left, baseY);
    final hip = Offset(left + (right - left) * 0.35, baseY - 4);
    final shoulder = Offset(right - 20, baseY + dip * 0.3);
    final elbow = Offset(shoulder.dx - 4, shoulder.dy + dip * 0.6 + 16);
    final hand = Offset(shoulder.dx - 2, baseY + 46);

    return _Figure(
      head: Offset(right, shoulder.dy - 6),
      bones: [(foot, hip), (hip, shoulder), (shoulder, elbow), (elbow, hand)],
    );
  }

  _Figure _jumpingJack(Size size, double t) {
    final cx = size.width / 2;
    final shoulderY = size.height * 0.32;
    final hipY = size.height * 0.52;
    final footY = size.height * 0.88;
    final armSpread = 20 + t * 40;
    final armLift = t * size.height * 0.22;
    final legSpread = 14 + t * 30;

    final shoulder = Offset(cx, shoulderY);
    final hip = Offset(cx, hipY);
    final handL = Offset(cx - armSpread, shoulderY - armLift);
    final handR = Offset(cx + armSpread, shoulderY - armLift);
    final footL = Offset(cx - legSpread, footY);
    final footR = Offset(cx + legSpread, footY);

    return _Figure(
      head: Offset(cx, shoulderY - 22),
      bones: [(shoulder, hip), (shoulder, handL), (shoulder, handR), (hip, footL), (hip, footR)],
    );
  }

  _Figure _neckStretch(Size size, double t) {
    final cx = size.width / 2;
    final shoulderY = size.height * 0.42;
    final hipY = size.height * 0.68;
    final headOffset = (t - 0.5) * size.width * 0.32;

    final shoulder = Offset(cx, shoulderY);
    final hip = Offset(cx, hipY);
    final head = Offset(cx + headOffset, shoulderY - 34);
    final handL = Offset(cx - 30, shoulderY + 20);
    final handR = Offset(cx + 30, shoulderY + 20);
    final footL = Offset(cx - 16, size.height * 0.92);
    final footR = Offset(cx + 16, size.height * 0.92);

    return _Figure(
      head: head,
      bones: [
        (shoulder, hip),
        (shoulder, handL),
        (shoulder, handR),
        (hip, footL),
        (hip, footR),
        (shoulder, head),
      ],
    );
  }
}
