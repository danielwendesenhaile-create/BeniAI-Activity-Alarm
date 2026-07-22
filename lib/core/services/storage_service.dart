import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Thin wrapper around [FirebaseStorage] for uploading the reference photos
/// captured when a user saves a reusable activity template.
class StorageService {
  StorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads a JPEG reference photo for a saved activity template and
  /// returns its public download URL.
  Future<String> uploadActivityReferenceImage({
    required String uid,
    required String templateId,
    required Uint8List jpegBytes,
  }) async {
    final ref = _storage.ref('users/$uid/activity_templates/$templateId.jpg');
    await ref.putData(jpegBytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> deleteActivityReferenceImage({required String uid, required String templateId}) {
    return _storage.ref('users/$uid/activity_templates/$templateId.jpg').delete();
  }
}
