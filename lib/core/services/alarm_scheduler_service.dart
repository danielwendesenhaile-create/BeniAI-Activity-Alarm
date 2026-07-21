import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:rxdart/rxdart.dart';

import '../../models/alarm_model.dart';

/// Wraps the native `alarm` plugin: turns our Firestore-backed [AlarmModel]
/// into scheduled OS-level alarms that ring reliably even when the app is
/// backgrounded or (on Android) killed.
class AlarmSchedulerService {
  Future<void> init() => Alarm.init();

  /// Fires whenever any scheduled alarm starts ringing.
  ValueStream<AlarmSet> get ringingStream => Alarm.ringing;

  Future<bool> schedule(AlarmModel alarm) {
    final settings = AlarmSettings(
      id: alarm.nativeAlarmId,
      dateTime: alarm.nextOccurrence(),
      assetAudioPath: alarm.soundAssetPath,
      loopAudio: true,
      vibrate: true,
      androidFullScreenIntent: true,
      warningNotificationOnKill: true,
      volumeSettings: const VolumeSettings.fixed(volume: 0.9),
      notificationSettings: NotificationSettings(
        title: alarm.label.isNotEmpty ? alarm.label : 'BeniAI Alarm',
        body:
            'Do ${alarm.targetReps} ${alarm.activityPreset.unitLabel} of '
            '${alarm.activityLabel} to stop the alarm.',
        stopButton: null, // Force opening the app to verify the activity.
      ),
      payload: alarm.id,
    );
    return Alarm.set(alarmSettings: settings);
  }

  Future<bool> cancel(AlarmModel alarm) => Alarm.stop(alarm.nativeAlarmId);

  Future<bool> stopById(int nativeId) => Alarm.stop(nativeId);

  Future<bool> isRinging(int nativeId) => Alarm.isRinging(nativeId);
}
