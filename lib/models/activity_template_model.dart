import 'package:cloud_firestore/cloud_firestore.dart';

import 'activity_model.dart';

/// A user-saved, reusable activity - recorded once via the camera and then
/// picked again for any future alarm, persisted at
/// `users/{uid}/activityTemplates/{templateId}`.
///
/// [referenceImageBase64] is the photo captured when the activity was
/// demonstrated, stored inline as base64 (no Cloud Storage - that requires
/// Firebase's paid Blaze plan). It's shown to OpenAI vision alongside the
/// live camera feed at alarm-ring time so verification is grounded in what
/// the user actually showed BeniAI, rather than a generic description
/// alone. Null when no photo was captured, or it was too large to store
/// (Firestore caps documents at 1MB).
class ActivityTemplate {
  final String id;
  final String userId;
  final String name;
  final ActivityType activityType;
  final String? referenceImageBase64;
  final int defaultTarget;
  final DateTime createdAt;

  const ActivityTemplate({
    required this.id,
    required this.userId,
    required this.name,
    required this.activityType,
    this.referenceImageBase64,
    required this.defaultTarget,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'activityType': activityType.id,
      'referenceImageBase64': referenceImageBase64,
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
      referenceImageBase64: map['referenceImageBase64'] as String?,
      defaultTarget: map['defaultTarget'] as int? ?? 1,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory ActivityTemplate.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ActivityTemplate.fromMap(doc.id, doc.data() ?? const {});
  }
}
