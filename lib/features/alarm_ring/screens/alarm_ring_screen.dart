import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/analytics_service.dart';
import '../../alarms/providers/alarm_providers.dart';

/// Full-screen alarm-ringing UI. The user cannot dismiss this by going
/// back - the only way out is completing the activity on the verification
/// screen, matching a real alarm clock.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({super.key, required this.alarmId});

  final String alarmId;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  bool _tracked = false;

  @override
  Widget build(BuildContext context) {
    final alarm = ref.watch(alarmByIdProvider(widget.alarmId));

    if (!_tracked) {
      _tracked = true;
      ref.read(analyticsServiceProvider).track(AnalyticsEvents.alarmRang, {
        'alarm_id': widget.alarmId,
      });
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.deepPurple.shade900,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat.jm().format(DateTime.now()),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  alarm?.label ?? 'Alarm',
                  style: const TextStyle(color: Colors.white70, fontSize: 20),
                ),
                const Spacer(),
                if (alarm != null) ...[
                  Icon(alarm.activityPreset.icon, size: 72, color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    '${alarm.targetReps} ${alarm.activityPreset.unitLabel} of '
                    '${alarm.activityLabel}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'to stop the alarm',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.deepPurple.shade900,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                    ),
                    onPressed: () {
                      context.pushReplacement(AppRoutes.verifyAlarm(widget.alarmId));
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text(
                      "I'm up - Start Activity",
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
