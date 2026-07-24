import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/activity_completion_model.dart';
import '../../models/activity_template_model.dart';
import '../../models/alarm_model.dart';
import '../../models/user_model.dart';

/// Firestore data access for user profiles, alarms and saved activities.
///
/// Layout:
///   users/{uid}                              -> AppUserModel
///   users/{uid}/alarms/{alarmId}              -> AlarmModel
///   users/{uid}/activityTemplates/{templateId} -> ActivityTemplate
///   users/{uid}/completions/{completionId}    -> ActivityCompletion
class FirestoreRepository {
  FirestoreRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  CollectionReference<Map<String, dynamic>> _alarmsFor(String uid) =>
      _users.doc(uid).collection('alarms');

  CollectionReference<Map<String, dynamic>> _activityTemplatesFor(String uid) =>
      _users.doc(uid).collection('activityTemplates');

  CollectionReference<Map<String, dynamic>> _completionsFor(String uid) =>
      _users.doc(uid).collection('completions');

  // ---- Users ----------------------------------------------------------

  /// Creates the user's profile document if it doesn't exist yet. Safe to
  /// call on every sign-in (idempotent). If [gender] is passed and the
  /// profile already exists without one set, it's merge-patched in - this
  /// covers the sign-up flow, where this may race with the app's generic
  /// post-auth bootstrap call (which doesn't know the chosen gender).
  Future<void> ensureUserProfile({
    required String uid,
    required String email,
    String? displayName,
    Gender? gender,
  }) async {
    final doc = _users.doc(uid);
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      final user = AppUserModel(
        uid: uid,
        email: email,
        displayName: displayName,
        gender: gender,
        isPremium: false,
        createdAt: DateTime.now(),
      );
      await doc.set(user.toMap());
      return;
    }

    if (gender != null && snapshot.data()?['gender'] == null) {
      await doc.set({'gender': gender.id}, SetOptions(merge: true));
    }
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

  Future<void> deleteActivityTemplate({required String uid, required String templateId}) {
    return _activityTemplatesFor(uid).doc(templateId).delete();
  }

  // ---- Completions --------------------------------------------------------

  /// Streams the user's completion history, most recent first.
  Stream<List<ActivityCompletion>> watchCompletions(String uid, {int limit = 100}) {
    return _completionsFor(uid)
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ActivityCompletion.fromDoc).toList());
  }

  Future<void> createCompletion(ActivityCompletion completion) {
    final doc = _completionsFor(completion.userId).doc();
    return doc.set(ActivityCompletion.fromMap(doc.id, completion.toMap()).toMap());
  }
}
