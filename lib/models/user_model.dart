import 'package:cloud_firestore/cloud_firestore.dart';

class AppUserModel {
  final String uid;
  final String email;
  final String? displayName;
  final bool isPremium;
  final DateTime createdAt;

  const AppUserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.isPremium,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'isPremium': isPremium,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory AppUserModel.fromMap(String uid, Map<String, dynamic> map) {
    return AppUserModel(
      uid: uid,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String?,
      isPremium: map['isPremium'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory AppUserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUserModel.fromMap(doc.id, doc.data() ?? const {});
  }
}
