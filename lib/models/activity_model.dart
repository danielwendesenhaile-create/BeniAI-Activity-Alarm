import 'package:flutter/material.dart';

/// The kind of physical activity an alarm requires before it will stop.
enum ActivityType { squats, pushUps, jumpingJacks, neckStretch, custom }

extension ActivityTypeJson on ActivityType {
  String get id => name;

  static ActivityType fromId(String id) =>
      ActivityType.values.firstWhere((t) => t.name == id, orElse: () => ActivityType.squats);
}

/// Static description of an activity the user can pick for an alarm.
class ActivityPreset {
  final ActivityType type;
  final String label;
  final String description;
  final IconData icon;

  /// Whether on-device pose detection can automatically count reps for
  /// this activity. Activities that can't be pose-counted fall back to
  /// OpenAI vision spot-checks.
  final bool supportsPoseDetection;

  final int defaultTarget;
  final String unitLabel;

  const ActivityPreset({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
    required this.supportsPoseDetection,
    required this.defaultTarget,
    this.unitLabel = 'reps',
  });

  static const List<ActivityPreset> all = [
    ActivityPreset(
      type: ActivityType.squats,
      label: 'Squats',
      description: 'Stand in front of the camera and squat to stop the alarm.',
      icon: Icons.accessibility_new,
      supportsPoseDetection: true,
      defaultTarget: 20,
    ),
    ActivityPreset(
      type: ActivityType.pushUps,
      label: 'Push-ups',
      description: 'Get on the floor in view of the camera and knock out reps.',
      icon: Icons.fitness_center,
      supportsPoseDetection: true,
      defaultTarget: 10,
    ),
    ActivityPreset(
      type: ActivityType.jumpingJacks,
      label: 'Jumping Jacks',
      description: 'Full body in frame, jump until you hit your target.',
      icon: Icons.sports_gymnastics,
      supportsPoseDetection: true,
      defaultTarget: 25,
    ),
    ActivityPreset(
      type: ActivityType.neckStretch,
      label: 'Neck Stretch',
      description:
          'Frame your head and shoulders. Turn your head fully to one side, '
          'then the other, to count one.',
      icon: Icons.accessibility,
      supportsPoseDetection: true,
      defaultTarget: 10,
      unitLabel: 'turns',
    ),
    ActivityPreset(
      type: ActivityType.custom,
      label: 'Custom',
      description:
          'Describe any activity (e.g. "make your bed", "brush your teeth"). '
          'BeniAI will use its camera vision to verify it for you.',
      icon: Icons.auto_awesome,
      supportsPoseDetection: false,
      defaultTarget: 1,
      unitLabel: 'times',
    ),
  ];

  static ActivityPreset byType(ActivityType type) =>
      all.firstWhere((a) => a.type == type, orElse: () => all.first);
}

/// How the app should verify the activity was actually performed.
enum VerificationMode {
  /// Real-time on-device pose detection only.
  pose,

  /// Periodic OpenAI vision spot-checks only.
  vision,

  /// Pose detection when available for the activity, OpenAI vision as a
  /// fallback / spot-check. This is the recommended default.
  hybrid,
}

extension VerificationModeJson on VerificationMode {
  String get id => name;

  static VerificationMode fromId(String? id) => VerificationMode.values.firstWhere(
    (m) => m.name == id,
    orElse: () => VerificationMode.hybrid,
  );
}
