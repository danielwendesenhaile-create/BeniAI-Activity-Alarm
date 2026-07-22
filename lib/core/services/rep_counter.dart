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

  /// What the tracker last saw and why the frame was accepted or rejected -
  /// shown as an on-screen readout so tracking issues can be diagnosed from
  /// a screenshot instead of guessing blind.
  String _debugInfo = 'no pose yet';
  String get debugInfo => _debugInfo;

  static const _minLikelihood = 0.6;

  /// Fraction of all landmarks ML Kit must report with confidence for a
  /// frame to be treated as "a full person is actually in view". Pose
  /// models can hallucinate a plausible-looking skeleton (with a couple of
  /// confidently-placed joints) from a partial view - like a hand or leg
  /// held close to the camera - which would otherwise fool the angle check
  /// below into counting a rep. Requiring most of the body to be visible
  /// filters that out. Only applies to full-body activities - a neck
  /// stretch is naturally framed on just the head/shoulders.
  static const _minVisibleFraction = 0.7;

  /// How many consecutive qualifying frames a joint must stay past a
  /// threshold before a phase change is accepted. Filters out single-frame
  /// pose-estimation jitter and quick incidental movements (e.g. reaching
  /// for the phone) that would otherwise look like a rep, without being so
  /// strict that real reps get missed when pose detection briefly loses
  /// confidence (occlusion, floor-level camera angle, etc).
  static const _requiredStreak = 2;

  /// How far the nose must swing to one side of the shoulder midpoint,
  /// as a fraction of shoulder width, to count as "turned" for a neck
  /// stretch. This is a first-pass estimate, not empirically tuned.
  static const _neckTurnThreshold = 0.15;

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
        if (!_hasFullBodyInFrame(pose)) {
          _debugInfo = 'rejected: not enough of the body is visible';
          return false;
        }
        // Squats need a standing, roughly upright torso - rejects a stray
        // limb or someone lying/sitting from faking knee-angle swings.
        if (!_hasTorso(pose, wantHorizontal: false)) {
          _debugInfo = 'rejected: torso is not upright (need standing squat posture)';
          return false;
        }
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
        if (!_hasFullBodyInFrame(pose)) {
          _debugInfo = 'rejected: not enough of the body is visible';
          return false;
        }
        // Push-ups need a roughly horizontal (plank) torso - rejects
        // someone standing and just bending an elbow, or a stray limb.
        if (!_hasTorso(pose, wantHorizontal: true)) {
          _debugInfo = 'rejected: torso is not horizontal (need plank posture)';
          return false;
        }
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
      case ActivityType.neckStretch:
        return _processNeckStretch(pose);
      case ActivityType.custom:
        // Not pose-countable; verified via OpenAI vision instead.
        return false;
    }
  }

  /// Rejects frames where only a fragment of the body is visible (e.g. a
  /// hand or leg held up to the camera), which pose models can otherwise
  /// render as a plausible-but-hallucinated full skeleton.
  bool _hasFullBodyInFrame(Pose pose) {
    if (pose.landmarks.isEmpty) return false;
    final confident = pose.landmarks.values.where((l) => l.likelihood >= _minLikelihood).length;
    return confident / pose.landmarks.length >= _minVisibleFraction;
  }

  /// Checks the shoulder-to-hip line is oriented the way the activity
  /// expects: mostly horizontal for a push-up plank, mostly vertical for a
  /// standing squat. Both landmarks must also be confidently visible.
  bool _hasTorso(Pose pose, {required bool wantHorizontal}) {
    final shoulder = _bestLandmark(
      pose,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
    );
    final hip = _bestLandmark(pose, PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);
    if (shoulder == null || hip == null) return false;

    final dx = (shoulder.x - hip.x).abs();
    final dy = (shoulder.y - hip.y).abs();
    if (dx == 0 && dy == 0) return false;

    return wantHorizontal ? dx >= dy : dy > dx;
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
    if (a == null || b == null || c == null) {
      _debugInfo = 'rejected: key joints not confidently visible';
      return false;
    }

    final angle = _angleAt(a, b, c);

    final candidate = angle <= downThreshold
        ? _Phase.down
        : angle >= upThreshold
        ? _Phase.up
        : null;

    final previous = _confirmPhase(candidate);
    _debugInfo =
        'angle=${angle.toStringAsFixed(0)}° phase=${_phase.name} '
        'reps=$_reps${_isWarmingUp ? ' (warming up)' : ''}';
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
      _debugInfo = 'rejected: full body not confidently visible';
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
    _debugInfo =
        'armsUp=$armsUp legsApart=$legsApart phase=${_phase.name} '
        'reps=$_reps${_isWarmingUp ? ' (warming up)' : ''}';
    if (previous == null) return false;

    if (previous == _Phase.up && _phase == _Phase.down && !_isWarmingUp) {
      _reps++;
      return true;
    }
    return false;
  }

  /// A neck stretch turns the head to one side and back. Tracked via the
  /// nose's horizontal offset from the shoulder midpoint, normalized by
  /// shoulder width so it works regardless of distance from the camera.
  /// One full left-then-right (or right-then-left) cycle counts as a rep.
  bool _processNeckStretch(Pose pose) {
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (nose == null ||
        leftShoulder == null ||
        rightShoulder == null ||
        nose.likelihood < _minLikelihood ||
        leftShoulder.likelihood < _minLikelihood ||
        rightShoulder.likelihood < _minLikelihood) {
      _debugInfo = 'rejected: face/shoulders not confidently visible';
      return false;
    }

    final shoulderWidth = (leftShoulder.x - rightShoulder.x).abs();
    if (shoulderWidth < 1) {
      _debugInfo = 'rejected: shoulders too close together to measure';
      return false;
    }

    final midShoulderX = (leftShoulder.x + rightShoulder.x) / 2;
    final offset = (nose.x - midShoulderX) / shoulderWidth;

    final candidate = offset <= -_neckTurnThreshold
        ? _Phase.down
        : offset >= _neckTurnThreshold
        ? _Phase.up
        : null;

    final previous = _confirmPhase(candidate);
    _debugInfo =
        'headOffset=${offset.toStringAsFixed(2)} phase=${_phase.name} '
        'reps=$_reps${_isWarmingUp ? ' (warming up)' : ''}';
    if (previous == null) return false;

    if (previous == _Phase.down && _phase == _Phase.up && !_isWarmingUp) {
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
