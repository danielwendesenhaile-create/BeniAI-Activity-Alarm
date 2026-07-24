import 'package:cloud_firestore/cloud_firestore.dart';

import 'activity_model.dart';

/// A record of a single completed alarm activity, persisted at
/// `users/{uid}/completions/{completionId}` - the app's own history of
/// what you actually did, independent of analytics.
class ActivityCompletion {
  final String id;
  final String userId;
  final String alarmId;
  final String alarmLabel;
  final ActivityType activityType;
  final String activityLabel;
  final int targetReps;
  final int completedReps;
  final DateTime completedAt;

  const ActivityCompletion({
    required this.id,
    required this.userId,
    required this.alarmId,
    required this.alarmLabel,
    required this.activityType,
    required this.activityLabel,
    required this.targetReps,
    required this.completedReps,
    required this.completedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'alarmId': alarmId,
      'alarmLabel': alarmLabel,
      'activityType': activityType.id,
      'activityLabel': activityLabel,
      'targetReps': targetReps,
      'completedReps': completedReps,
      'completedAt': Timestamp.fromDate(completedAt),
    };
  }

  factory ActivityCompletion.fromMap(String id, Map<String, dynamic> map) {
    return ActivityCompletion(
      id: id,
      userId: map['userId'] as String? ?? '',
      alarmId: map['alarmId'] as String? ?? '',
      alarmLabel: map['alarmLabel'] as String? ?? 'Alarm',
      activityType: ActivityTypeJson.fromId(map['activityType'] as String? ?? ''),
      activityLabel: map['activityLabel'] as String? ?? '',
      targetReps: map['targetReps'] as int? ?? 0,
      completedReps: map['completedReps'] as int? ?? 0,
      completedAt: (map['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory ActivityCompletion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ActivityCompletion.fromMap(doc.id, doc.data() ?? const {});
  }
}
