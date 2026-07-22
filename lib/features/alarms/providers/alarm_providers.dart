import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../models/activity_template_model.dart';
import '../../../models/alarm_model.dart';
import '../../auth/providers/auth_providers.dart';

/// Streams the signed-in user's alarms, ordered by time of day.
final userAlarmsProvider = StreamProvider<List<AlarmModel>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <AlarmModel>[]);
  return ref.watch(firestoreRepositoryProvider).watchAlarms(uid);
});

/// Streams the signed-in user's saved (recorded-and-named) activities.
final userActivityTemplatesProvider = StreamProvider<List<ActivityTemplate>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const <ActivityTemplate>[]);
  return ref.watch(firestoreRepositoryProvider).watchActivityTemplates(uid);
});

/// Looks up a single alarm by id from the currently loaded list, used by the
/// alarm-ring/verification screens which are given only an id via routing.
final alarmByIdProvider = Provider.family<AlarmModel?, String>((ref, id) {
  final alarms = ref.watch(userAlarmsProvider).value ?? const [];
  for (final alarm in alarms) {
    if (alarm.id == id) return alarm;
  }
  return null;
});
