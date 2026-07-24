import 'package:cloud_firestore/cloud_firestore.dart';

import 'activity_model.dart';

/// A user-configured alarm, persisted in Firestore at
/// `users/{uid}/alarms/{alarmId}`.
class AlarmModel {
  final String id;
  final String userId;
  final String label;

  /// Hour of day in 24h format (0-23).
  final int hour;

  /// Minute of the hour (0-59).
  final int minute;

  /// Weekdays this alarm repeats on, using DateTime.monday(1)..sunday(7).
  /// Empty means "one time only".
  final Set<int> repeatDays;

  final String soundId;
  final String soundName;
  final String soundAssetPath;

  final ActivityType activityType;

  /// Display label for the activity, shown in the UI.
  final String activityLabel;

  final int targetReps;

  final bool isEnabled;
  final DateTime createdAt;

  const AlarmModel({
    required this.id,
    required this.userId,
    required this.label,
    required this.hour,
    required this.minute,
    required this.repeatDays,
    required this.soundId,
    required this.soundName,
    required this.soundAssetPath,
    required this.activityType,
    required this.activityLabel,
    required this.targetReps,
    required this.isEnabled,
    required this.createdAt,
  });

  /// A stable 32-bit id derived from the Firestore document id, used to
  /// schedule the alarm with the native `alarm` plugin (which needs an int).
  int get nativeAlarmId => id.hashCode & 0x7fffffff;

  ActivityPreset get activityPreset => ActivityPreset.byType(activityType);

  String get timeLabel {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Next DateTime (in local time) this alarm should ring at, considering
  /// [repeatDays]. If [repeatDays] is empty, returns the next occurrence of
  /// the alarm's time (today if still in the future, else tomorrow).
  DateTime nextOccurrence({DateTime? from}) {
    final now = from ?? DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);

    if (repeatDays.isEmpty) {
      if (!candidate.isAfter(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }

    for (var i = 0; i < 8; i++) {
      final day = candidate.add(Duration(days: i));
      final isRepeatDay = repeatDays.contains(day.weekday);
      final isFutureEnough = day.isAfter(now);
      if (isRepeatDay && isFutureEnough) {
        return DateTime(day.year, day.month, day.day, hour, minute);
      }
    }
    return candidate.add(const Duration(days: 7));
  }

  AlarmModel copyWith({
    String? label,
    int? hour,
    int? minute,
    Set<int>? repeatDays,
    String? soundId,
    String? soundName,
    String? soundAssetPath,
    ActivityType? activityType,
    String? activityLabel,
    int? targetReps,
    bool? isEnabled,
  }) {
    return AlarmModel(
      id: id,
      userId: userId,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      repeatDays: repeatDays ?? this.repeatDays,
      soundId: soundId ?? this.soundId,
      soundName: soundName ?? this.soundName,
      soundAssetPath: soundAssetPath ?? this.soundAssetPath,
      activityType: activityType ?? this.activityType,
      activityLabel: activityLabel ?? this.activityLabel,
      targetReps: targetReps ?? this.targetReps,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'label': label,
      'hour': hour,
      'minute': minute,
      'repeatDays': repeatDays.toList()..sort(),
      'soundId': soundId,
      'soundName': soundName,
      'soundAssetPath': soundAssetPath,
      'activityType': activityType.id,
      'activityLabel': activityLabel,
      'targetReps': targetReps,
      'isEnabled': isEnabled,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory AlarmModel.fromMap(String id, Map<String, dynamic> map) {
    return AlarmModel(
      id: id,
      userId: map['userId'] as String? ?? '',
      label: map['label'] as String? ?? 'Alarm',
      hour: map['hour'] as int? ?? 7,
      minute: map['minute'] as int? ?? 0,
      repeatDays: ((map['repeatDays'] as List?) ?? const []).map((e) => e as int).toSet(),
      soundId: map['soundId'] as String? ?? 'classic',
      soundName: map['soundName'] as String? ?? 'Classic',
      soundAssetPath: map['soundAssetPath'] as String? ?? 'assets/sounds/classic.wav',
      activityType: ActivityTypeJson.fromId(map['activityType'] as String? ?? ''),
      activityLabel: map['activityLabel'] as String? ?? 'Squats',
      targetReps: map['targetReps'] as int? ?? 20,
      isEnabled: map['isEnabled'] as bool? ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory AlarmModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AlarmModel.fromMap(doc.id, doc.data() ?? const {});
  }
}
