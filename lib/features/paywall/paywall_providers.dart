import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/service_providers.dart';

/// Streams whether the current user has an active Superwall subscription.
final isSubscribedProvider = StreamProvider<bool>((ref) {
  return ref.watch(paywallServiceProvider).isSubscribedStream;
});

/// Free tier limit: how many alarms a non-premium user can have active.
const int freeAlarmLimit = 1;
