import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../models/user_model.dart';

/// Emits the current Firebase [User], or null if signed out.
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthServiceProvider).authStateChanges;
});

/// Convenience accessor for the signed-in uid, or null.
final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateChangesProvider).value?.uid;
});

/// Streams the current user's Firestore profile (premium status, etc).
final currentUserProfileProvider = StreamProvider<AppUserModel?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreRepositoryProvider).watchUser(uid);
});

/// Runs once per signed-in user: makes sure their Firestore profile exists
/// and identifies them to analytics/paywall SDKs. Safe to `watch` from any
/// widget - re-runs only when the signed-in user changes.
final userBootstrapProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(authStateChangesProvider).value;
  if (user == null) return;

  await ref
      .read(firestoreRepositoryProvider)
      .ensureUserProfile(uid: user.uid, email: user.email ?? '', displayName: user.displayName);
  ref.read(analyticsServiceProvider).identify(user.uid);
  await ref.read(paywallServiceProvider).identify(user.uid);
});
