import 'dart:math';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../models/activity_model.dart';

enum _Phase { up, down, unknown }

/// Counts repetitions of a pose-countable [ActivityType] from a stream of
/// ML Kit [Pose] results using a simple angle/position state machine.
///
/// This is intentionally low-tech (no ML rep-counting model) so it runs
/// fully on-device with no extra dependencies: it tracks a joint angle (or
/// limb position) between two thresholds and counts a rep every time the
/// body completes a down-then-up (or open-then-closed) cycle.
class RepCounter {
  RepCounter(this.activityType);

  final ActivityType activityType;

  int _reps = 0;
  _Phase _phase = _Phase.unknown;

  static const _minLikelihood = 0.5;

  int get reps => _reps;

  void reset() {
    _reps = 0;
    _phase = _Phase.unknown;
  }

  /// Feeds a newly detected [pose]. Returns true if this frame completed a
  /// new rep.
  bool processPose(Pose pose) {
    switch (activityType) {
      case ActivityType.squats:
        return _processAngleBased(
          pose,
          shoulderOrHip: PoseLandmarkType.leftHip,
          altShoulderOrHip: PoseLandmarkType.rightHip,
          joint: PoseLandmarkType.leftKnee,
          altJoint: PoseLandmarkType.rightKnee,
          end: PoseLandmarkType.leftAnkle,
          altEnd: PoseLandmarkType.rightAnkle,
          downThreshold: 100,
          upThreshold: 160,
        );
      case ActivityType.pushUps:
        return _processAngleBased(
          pose,
          shoulderOrHip: PoseLandmarkType.leftShoulder,
          altShoulderOrHip: PoseLandmarkType.rightShoulder,
          joint: PoseLandmarkType.leftElbow,
          altJoint: PoseLandmarkType.rightElbow,
          end: PoseLandmarkType.leftWrist,
          altEnd: PoseLandmarkType.rightWrist,
          downThreshold: 95,
          upThreshold: 155,
        );
      case ActivityType.jumpingJacks:
        return _processJumpingJack(pose);
      case ActivityType.custom:
        // Not pose-countable; verified via OpenAI vision instead.
        return false;
    }
  }

  bool _processAngleBased(
    Pose pose, {
    required PoseLandmarkType shoulderOrHip,
    required PoseLandmarkType altShoulderOrHip,
    required PoseLandmarkType joint,
    required PoseLandmarkType altJoint,
    required PoseLandmarkType end,
    required PoseLandmarkType altEnd,
    required double downThreshold,
    required double upThreshold,
  }) {
    final a = _bestLandmark(pose, shoulderOrHip, altShoulderOrHip);
    final b = _bestLandmark(pose, joint, altJoint);
    final c = _bestLandmark(pose, end, altEnd);
    if (a == null || b == null || c == null) return false;

    final angle = _angleAt(a, b, c);

    if (angle <= downThreshold) {
      _phase = _Phase.down;
    } else if (angle >= upThreshold) {
      if (_phase == _Phase.down) {
        _reps++;
        _phase = _Phase.up;
        return true;
      }
      _phase = _Phase.up;
    }
    return false;
  }

  bool _processJumpingJack(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    final required = [
      leftShoulder,
      rightShoulder,
      leftWrist,
      rightWrist,
      leftHip,
      rightHip,
      leftAnkle,
      rightAnkle,
    ];
    if (required.any((l) => l == null || l.likelihood < _minLikelihood)) {
      return false;
    }

    final armsUp = leftWrist!.y < leftShoulder!.y && rightWrist!.y < rightShoulder!.y;

    final hipWidth = (leftHip!.x - rightHip!.x).abs();
    final ankleWidth = (leftAnkle!.x - rightAnkle!.x).abs();
    final legsApart = hipWidth > 0 && ankleWidth > hipWidth * 1.4;

    final isOpen = armsUp && legsApart;
    final isClosed = !armsUp && !legsApart;

    if (isOpen) {
      _phase = _Phase.up;
    } else if (isClosed) {
      if (_phase == _Phase.up) {
        _reps++;
        _phase = _Phase.down;
        return true;
      }
      _phase = _Phase.down;
    }
    return false;
  }

  PoseLandmark? _bestLandmark(Pose pose, PoseLandmarkType type, PoseLandmarkType alt) {
    final primary = pose.landmarks[type];
    if (primary != null && primary.likelihood >= _minLikelihood) return primary;
    final fallback = pose.landmarks[alt];
    if (fallback != null && fallback.likelihood >= _minLikelihood) return fallback;
    return null;
  }

  /// Angle in degrees at vertex [b], formed by rays b->a and b->c.
  double _angleAt(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final abX = a.x - b.x;
    final abY = a.y - b.y;
    final cbX = c.x - b.x;
    final cbY = c.y - b.y;

    final dot = abX * cbX + abY * cbY;
    final magAb = sqrt(abX * abX + abY * abY);
    final magCb = sqrt(cbX * cbX + cbY * cbY);
    if (magAb == 0 || magCb == 0) return 180;

    final cosAngle = (dot / (magAb * magCb)).clamp(-1.0, 1.0);
    return acos(cosAngle) * 180 / pi;
  }
}
