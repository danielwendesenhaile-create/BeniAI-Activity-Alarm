import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../alarms/providers/alarm_providers.dart';
import '../widgets/activity_stick_figure.dart';

/// Shown after "I'm up" and before the camera opens: a looping animated
/// demonstration of exactly what movement the alarm's activity requires,
/// so the user knows what to do before tracking starts.
class ActivityGuideScreen extends ConsumerWidget {
  const ActivityGuideScreen({super.key, required this.alarmId});

  final String alarmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarm = ref.watch(alarmByIdProvider(alarmId));

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.deepPurple.shade900,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: alarm == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Column(
                    children: [
                      const Spacer(),
                      Text(
                        alarm.activityLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This is the movement BeniAI will track',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: ActivityStickFigure(activityType: alarm.activityType),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        alarm.activityPreset.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.deepPurple.shade900,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                          onPressed: () =>
                              context.pushReplacement(AppRoutes.verifyAlarm(alarmId)),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text(
                            'Start Activity',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
