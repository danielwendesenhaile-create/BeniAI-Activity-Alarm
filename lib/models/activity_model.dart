import 'package:flutter/material.dart';

/// The kind of physical activity an alarm requires before it will stop.
///
/// All of these are counted live, continuously, and entirely on-device via
/// Google's MediaPipe-based pose detector (through ML Kit) - there is no
/// cloud AI vision call anywhere in the verification path.
enum ActivityType { squats, pushUps, jumpingJacks, neckStretch }

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
  final int defaultTarget;
  final String unitLabel;

  const ActivityPreset({
    required this.type,
    required this.label,
    required this.description,
    required this.icon,
    required this.defaultTarget,
    this.unitLabel = 'reps',
  });

  static const List<ActivityPreset> all = [
    ActivityPreset(
      type: ActivityType.squats,
      label: 'Squats',
      description: 'Stand in front of the camera and squat to stop the alarm.',
      icon: Icons.accessibility_new,
      defaultTarget: 20,
    ),
    ActivityPreset(
      type: ActivityType.pushUps,
      label: 'Push-ups',
      description: 'Get on the floor in view of the camera and knock out reps.',
      icon: Icons.fitness_center,
      defaultTarget: 10,
    ),
    ActivityPreset(
      type: ActivityType.jumpingJacks,
      label: 'Jumping Jacks',
      description: 'Full body in frame, jump until you hit your target.',
      icon: Icons.sports_gymnastics,
      defaultTarget: 25,
    ),
    ActivityPreset(
      type: ActivityType.neckStretch,
      label: 'Neck Stretch',
      description:
          'Frame your head and shoulders. Turn your head fully to one side, '
          'then the other, to count one.',
      icon: Icons.accessibility,
      defaultTarget: 10,
      unitLabel: 'turns',
    ),
  ];

  static ActivityPreset byType(ActivityType type) =>
      all.firstWhere((a) => a.type == type, orElse: () => all.first);
}
