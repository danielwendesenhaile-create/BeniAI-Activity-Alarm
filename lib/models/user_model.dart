import 'package:cloud_firestore/cloud_firestore.dart';

/// Used to pick which version (male/female) of the activity demo videos to
/// show on the pre-activity guide screen. Optional - older accounts (or
/// anyone who signed up before this existed) simply have a null gender and
/// fall back to a default video set.
enum Gender { male, female }

extension GenderJson on Gender {
  String get id => name;

  static Gender? fromId(String? id) {
    for (final g in Gender.values) {
      if (g.name == id) return g;
    }
    return null;
  }
}

class AppUserModel {
  final String uid;
  final String email;
  final String? displayName;
  final Gender? gender;
  final bool isPremium;
  final DateTime createdAt;

  const AppUserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.gender,
    required this.isPremium,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'gender': gender?.id,
      'isPremium': isPremium,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory AppUserModel.fromMap(String uid, Map<String, dynamic> map) {
    return AppUserModel(
      uid: uid,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String?,
      gender: GenderJson.fromId(map['gender'] as String?),
      isPremium: map['isPremium'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory AppUserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUserModel.fromMap(doc.id, doc.data() ?? const {});
  }
}
