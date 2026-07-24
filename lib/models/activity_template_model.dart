import 'package:cloud_firestore/cloud_firestore.dart';

import 'activity_model.dart';

/// A user-saved, reusable activity - detected once via the camera (or
/// picked manually) and named for reuse on any future alarm, persisted at
/// `users/{uid}/activityTemplates/{templateId}`.
class ActivityTemplate {
  final String id;
  final String userId;
  final String name;
  final ActivityType activityType;
  final int defaultTarget;
  final DateTime createdAt;

  const ActivityTemplate({
    required this.id,
    required this.userId,
    required this.name,
    required this.activityType,
    required this.defaultTarget,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'activityType': activityType.id,
      'defaultTarget': defaultTarget,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory ActivityTemplate.fromMap(String id, Map<String, dynamic> map) {
    return ActivityTemplate(
      id: id,
      userId: map['userId'] as String? ?? '',
      name: map['name'] as String? ?? 'Activity',
      activityType: ActivityTypeJson.fromId(map['activityType'] as String? ?? ''),
      defaultTarget: map['defaultTarget'] as int? ?? 1,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory ActivityTemplate.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ActivityTemplate.fromMap(doc.id, doc.data() ?? const {});
  }
}
