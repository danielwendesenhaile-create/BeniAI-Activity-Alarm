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
  RepCounter(this.activityType) {
    start();
  }

  final ActivityType activityType;

  int _reps = 0;
  _Phase _phase = _Phase.unknown;

  _Phase? _pendingPhase;
  int _pendingStreak = 0;
  DateTime _warmUntil = DateTime.now();

  static const _minLikelihood = 0.5;

  /// How many consecutive qualifying frames a joint must stay past a
  /// threshold before a phase change is accepted. Filters out single-frame
  /// pose-estimation jitter and quick incidental movements (e.g. reaching
  /// for the phone) that would otherwise look like a rep.
  static const _requiredStreak = 4;

  /// Reps completed in this window are ignored while the user is still
  /// getting into frame/position right after tracking starts.
  static const _warmUpDuration = Duration(milliseconds: 1200);

  int get reps => _reps;

  /// (Re)arms the counter: clears any counted reps and starts a fresh
  /// warm-up window. Call this right when camera tracking actually begins,
  /// not just when the counter is constructed, if there's a gap between
  /// the two (e.g. camera initialization).
  void start() {
    _reps = 0;
    _phase = _Phase.unknown;
    _pendingPhase = null;
    _pendingStreak = 0;
    _warmUntil = DateTime.now().add(_warmUpDuration);
  }

  void reset() => start();

  /// Resets phase-tracking and starts a fresh warm-up window without
  /// clearing the rep count. Call this when frame processing resumes after
  /// a pause (e.g. after an OpenAI spot-check photo capture) so a few
  /// seconds of no pose data can't be misread as a phase jump, but progress
  /// already made isn't lost.
  void rearm() {
    _phase = _Phase.unknown;
    _pendingPhase = null;
    _pendingStreak = 0;
    _warmUntil = DateTime.now().add(_warmUpDuration);
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

    final candidate = angle <= downThreshold
        ? _Phase.down
        : angle >= upThreshold
        ? _Phase.up
        : null;

    final previous = _confirmPhase(candidate);
    if (previous == null) return false;

    if (previous == _Phase.down && _phase == _Phase.up && !_isWarmingUp) {
      _reps++;
      return true;
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

    final candidate = isOpen
        ? _Phase.up
        : isClosed
        ? _Phase.down
        : null;

    final previous = _confirmPhase(candidate);
    if (previous == null) return false;

    if (previous == _Phase.up && _phase == _Phase.down && !_isWarmingUp) {
      _reps++;
      return true;
    }
    return false;
  }

  bool get _isWarmingUp => DateTime.now().isBefore(_warmUntil);

  /// Advances the debounce state machine toward [candidate]. Returns the
  /// previous confirmed phase if [candidate] has now been stable for
  /// [_requiredStreak] consecutive frames and represents an actual change
  /// (updating [_phase] as a side effect); returns null otherwise (no
  /// change yet, or the pose was ambiguous between thresholds).
  _Phase? _confirmPhase(_Phase? candidate) {
    if (candidate == null || candidate == _phase) {
      _pendingPhase = null;
      _pendingStreak = 0;
      return null;
    }

    if (_pendingPhase == candidate) {
      _pendingStreak++;
    } else {
      _pendingPhase = candidate;
      _pendingStreak = 1;
    }

    if (_pendingStreak < _requiredStreak) return null;

    _pendingPhase = null;
    _pendingStreak = 0;
    final previous = _phase;
    _phase = candidate;
    return previous;
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
