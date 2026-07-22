import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/activity_template_model.dart';
import '../../models/alarm_model.dart';
import '../../models/user_model.dart';

/// Firestore data access for user profiles, alarms and saved activities.
///
/// Layout:
///   users/{uid}                              -> AppUserModel
///   users/{uid}/alarms/{alarmId}              -> AlarmModel
///   users/{uid}/activityTemplates/{templateId} -> ActivityTemplate
class FirestoreRepository {
  FirestoreRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  CollectionReference<Map<String, dynamic>> _alarmsFor(String uid) =>
      _users.doc(uid).collection('alarms');

  CollectionReference<Map<String, dynamic>> _activityTemplatesFor(String uid) =>
      _users.doc(uid).collection('activityTemplates');

  // ---- Users ----------------------------------------------------------

  Future<void> ensureUserProfile({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    final doc = _users.doc(uid);
    final snapshot = await doc.get();
    if (snapshot.exists) return;

    final user = AppUserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      isPremium: false,
      createdAt: DateTime.now(),
    );
    await doc.set(user.toMap());
  }

  Stream<AppUserModel?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((doc) => doc.exists ? AppUserModel.fromDoc(doc) : null);
  }

  Future<void> setPremiumStatus(String uid, bool isPremium) {
    return _users.doc(uid).set({'isPremium': isPremium}, SetOptions(merge: true));
  }

  // ---- Alarms -----------------------------------------------------------

  Stream<List<AlarmModel>> watchAlarms(String uid) {
    return _alarmsFor(uid)
        .orderBy('hour')
        .snapshots()
        .map(
          (snap) => snap.docs.map(AlarmModel.fromDoc).toList()
            ..sort((a, b) {
              final byTime = (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
              return byTime != 0 ? byTime : a.createdAt.compareTo(b.createdAt);
            }),
        );
  }

  Future<AlarmModel> createAlarm(AlarmModel alarm) async {
    final doc = _alarmsFor(alarm.userId).doc();
    final withId = AlarmModel.fromMap(doc.id, alarm.toMap());
    await doc.set(withId.toMap());
    return withId;
  }

  Future<void> updateAlarm(AlarmModel alarm) {
    return _alarmsFor(alarm.userId).doc(alarm.id).set(alarm.toMap());
  }

  Future<void> deleteAlarm({required String uid, required String alarmId}) {
    return _alarmsFor(uid).doc(alarmId).delete();
  }

  Future<void> setAlarmEnabled({
    required String uid,
    required String alarmId,
    required bool isEnabled,
  }) {
    return _alarmsFor(uid).doc(alarmId).set({'isEnabled': isEnabled}, SetOptions(merge: true));
  }

  // ---- Activity templates -----------------------------------------------

  Stream<List<ActivityTemplate>> watchActivityTemplates(String uid) {
    return _activityTemplatesFor(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ActivityTemplate.fromDoc).toList());
  }

  Future<ActivityTemplate> createActivityTemplate(ActivityTemplate template) async {
    final doc = _activityTemplatesFor(template.userId).doc();
    final withId = ActivityTemplate.fromMap(doc.id, template.toMap());
    await doc.set(withId.toMap());
    return withId;
  }

  Future<void> updateActivityTemplate(ActivityTemplate template) {
    return _activityTemplatesFor(template.userId).doc(template.id).set(template.toMap());
  }

  Future<void> deleteActivityTemplate({required String uid, required String templateId}) {
    return _activityTemplatesFor(uid).doc(templateId).delete();
  }
}
