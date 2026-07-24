import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/analytics_service.dart';
import '../../../models/alarm_model.dart';
import '../../paywall/paywall_providers.dart';
import '../providers/alarm_providers.dart';
import '../widgets/alarm_card.dart';

class AlarmListScreen extends ConsumerWidget {
  const AlarmListScreen({super.key});

  Future<void> _onAddPressed(BuildContext context, WidgetRef ref) async {
    final alarms = ref.read(userAlarmsProvider).value ?? const [];
    final isSubscribed = ref.read(isSubscribedProvider).value ?? false;

    if (!isSubscribed && alarms.length >= freeAlarmLimit) {
      ref.read(analyticsServiceProvider).track(AnalyticsEvents.paywallViewed, {
        'source': 'alarm_limit',
      });
      await ref
          .read(paywallServiceProvider)
          .presentPaywall(
            onUnlocked: () {
              if (context.mounted) context.push(AppRoutes.newAlarm);
            },
          );
      return;
    }

    if (context.mounted) context.push(AppRoutes.newAlarm);
  }

  Future<void> _toggleAlarm(WidgetRef ref, AlarmModel alarm, bool enabled) async {
    final repo = ref.read(firestoreRepositoryProvider);
    final scheduler = ref.read(alarmSchedulerServiceProvider);

    await repo.setAlarmEnabled(uid: alarm.userId, alarmId: alarm.id, isEnabled: enabled);
    if (enabled) {
      await scheduler.schedule(alarm);
    } else {
      await scheduler.cancel(alarm);
    }
    ref.read(analyticsServiceProvider).track(AnalyticsEvents.alarmToggled, {
      'alarm_id': alarm.id,
      'enabled': enabled,
    });
  }

  Future<void> _deleteAlarm(WidgetRef ref, AlarmModel alarm) async {
    await ref.read(alarmSchedulerServiceProvider).cancel(alarm);
    await ref.read(firestoreRepositoryProvider).deleteAlarm(uid: alarm.userId, alarmId: alarm.id);
    ref.read(analyticsServiceProvider).track(AnalyticsEvents.alarmDeleted, {'alarm_id': alarm.id});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(userAlarmsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Alarms'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Activity history',
            onPressed: () => context.push(AppRoutes.history),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: alarmsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Failed to load alarms: $error')),
        data: (alarms) {
          if (alarms.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bedtime_outlined, size: 72, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('No alarms yet', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'Create an alarm and pick an activity you\'ll have to '
                      'do on camera before it will stop ringing.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: alarms.length,
            itemBuilder: (context, index) {
              final alarm = alarms[index];
              return AlarmCard(
                alarm: alarm,
                onTap: () => context.push(AppRoutes.editAlarm(alarm.id)),
                onToggle: (enabled) => _toggleAlarm(ref, alarm, enabled),
                onDelete: () => _deleteAlarm(ref, alarm),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onAddPressed(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Alarm'),
      ),
    );
  }
}
