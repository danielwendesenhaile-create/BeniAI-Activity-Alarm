import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/activity_model.dart';
import '../providers/alarm_providers.dart';

/// Shows the signed-in user's history of completed activities - the record
/// of every alarm they've actually stopped by finishing the activity,
/// newest first.
class ActivityHistoryScreen extends ConsumerWidget {
  const ActivityHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completionsAsync = ref.watch(userCompletionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity History')),
      body: completionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load history: $error')),
        data: (completions) {
          if (completions.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 72, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('No completions yet', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      "Every time you finish an alarm's activity, it'll show up here.",
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: completions.length,
            itemBuilder: (context, index) {
              final completion = completions[index];
              final preset = ActivityPreset.byType(completion.activityType);
              return Card(
                child: ListTile(
                  leading: Icon(preset.icon, color: Colors.deepPurpleAccent),
                  title: Text(completion.alarmLabel),
                  subtitle: Text(
                    '${completion.activityLabel} - ${completion.completedReps}/'
                    '${completion.targetReps} ${preset.unitLabel}',
                  ),
                  trailing: Text(
                    DateFormat.MMMd().add_jm().format(completion.completedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
