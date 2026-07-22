import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alarm_scheduler_service.dart';
import '../services/analytics_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_repository.dart';
import '../services/openai_service.dart';
import '../services/paywall_service.dart';
import '../services/storage_service.dart';

/// Singleton service instances, wired through Riverpod so screens/providers
/// can depend on them without a global service locator.
///
/// Services that need async setup ([AlarmSchedulerService.init],
/// [AnalyticsService.init], [PaywallService.init]) are initialized once in
/// `main()` before the app is rendered - see main.dart.

final firebaseAuthServiceProvider = Provider<FirebaseAuthService>((ref) {
  return FirebaseAuthService();
});

final firestoreRepositoryProvider = Provider<FirestoreRepository>((ref) {
  return FirestoreRepository();
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final openAIServiceProvider = Provider<OpenAIService>((ref) {
  final service = OpenAIService();
  ref.onDispose(service.dispose);
  return service;
});

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

final paywallServiceProvider = Provider<PaywallService>((ref) {
  final service = PaywallService();
  ref.onDispose(service.dispose);
  return service;
});

final alarmSchedulerServiceProvider = Provider<AlarmSchedulerService>((ref) {
  return AlarmSchedulerService();
});
