import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/alarm_sounds.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/analytics_service.dart';
import '../../../models/activity_model.dart';
import '../../../models/alarm_model.dart';
import '../../activity/screens/activity_camera_setup_screen.dart';
import '../../activity/widgets/activity_picker_sheet.dart';
import '../../activity/widgets/saved_activity_picker_sheet.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/alarm_providers.dart';
import '../widgets/sound_picker_sheet.dart';

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class AlarmEditScreen extends ConsumerStatefulWidget {
  const AlarmEditScreen({super.key, required this.alarmId});

  /// Null when creating a new alarm.
  final String? alarmId;

  @override
  ConsumerState<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends ConsumerState<AlarmEditScreen> {
  final _labelController = TextEditingController(text: 'Wake Up');

  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  final Set<int> _repeatDays = {};
  AlarmSound _sound = AlarmSounds.defaultSound;

  ActivityType _activityType = ActivityType.squats;
  String _activityLabel = ActivityPreset.byType(ActivityType.squats).label;
  int _targetReps = ActivityPreset.byType(ActivityType.squats).defaultTarget;
  String? _referenceImageBase64;

  bool _isSaving = false;
  bool _loadedExisting = false;

  bool get _isEditing => widget.alarmId != null;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _loadFrom(AlarmModel alarm) {
    _labelController.text = alarm.label;
    _time = TimeOfDay(hour: alarm.hour, minute: alarm.minute);
    _repeatDays
      ..clear()
      ..addAll(alarm.repeatDays);
    _sound = AlarmSounds.byId(alarm.soundId);
    _activityType = alarm.activityType;
    _activityLabel = alarm.activityLabel;
    _targetReps = alarm.targetReps;
    _referenceImageBase64 = alarm.referenceImageBase64;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickSound() async {
    final picked = await showSoundPickerSheet(context, currentSoundId: _sound.id);
    if (picked != null) setState(() => _sound = picked);
  }

  Future<void> _pickActivityManually() async {
    final result = await showActivityPickerSheet(context, current: _activityType);
    if (result == null) return;
    setState(() {
      _activityType = result.preset.type;
      _activityLabel = result.customLabel ?? result.preset.label;
      _targetReps = result.preset.defaultTarget;
      _referenceImageBase64 = null;
    });
  }

  Future<void> _pickActivityViaCamera() async {
    final result = await Navigator.of(context).push<ActivitySetupResult>(
      MaterialPageRoute(builder: (_) => const ActivityCameraSetupScreen()),
    );
    if (result == null) return;
    setState(() {
      _activityType = ActivityTypeJson.fromId(result.activityTypeId);
      _activityLabel = result.label;
      _targetReps = result.target;
      _referenceImageBase64 = result.referenceImageBase64;
    });
  }

  Future<void> _pickSavedActivity() async {
    final template = await showSavedActivityPickerSheet(context);
    if (template == null) return;
    setState(() {
      _activityType = template.activityType;
      _activityLabel = template.name;
      _targetReps = template.defaultTarget;
      _referenceImageBase64 = template.referenceImageBase64;
    });
  }

  Future<void> _save() async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(firestoreRepositoryProvider);
      final scheduler = ref.read(alarmSchedulerServiceProvider);
      final analytics = ref.read(analyticsServiceProvider);

      final draft = AlarmModel(
        id: widget.alarmId ?? '',
        userId: uid,
        label: _labelController.text.trim().isEmpty ? 'Alarm' : _labelController.text.trim(),
        hour: _time.hour,
        minute: _time.minute,
        repeatDays: _repeatDays,
        soundId: _sound.id,
        soundName: _sound.name,
        soundAssetPath: _sound.assetPath,
        activityType: _activityType,
        activityLabel: _activityLabel,
        targetReps: _targetReps,
        verificationMode: VerificationMode.hybrid,
        referenceImageBase64: _referenceImageBase64,
        isEnabled: true,
        createdAt: DateTime.now(),
      );

      final AlarmModel saved;
      if (_isEditing) {
        saved = draft;
        await repo.updateAlarm(saved);
        analytics.track(AnalyticsEvents.alarmUpdated, {'alarm_id': saved.id});
      } else {
        saved = await repo.createAlarm(draft);
        analytics.track(AnalyticsEvents.alarmCreated, {
          'alarm_id': saved.id,
          'activity_type': saved.activityType.id,
          'target': saved.targetReps,
        });
      }

      await scheduler.schedule(saved);

      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing && !_loadedExisting) {
      final alarm = ref.watch(alarmByIdProvider(widget.alarmId!));
      if (alarm != null) {
        _loadFrom(alarm);
        _loadedExisting = true;
      }
    }

    final preset = ActivityPreset.byType(_activityType);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Alarm' : 'New Alarm'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _time.format(context),
                  style: Theme.of(
                    context,
                  ).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 20),
          Text('Repeat', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: List.generate(7, (i) {
              final weekday = i + 1; // Monday = 1
              final selected = _repeatDays.contains(weekday);
              return ChoiceChip(
                label: Text(_weekdayLabels[i]),
                selected: selected,
                onSelected: (value) => setState(() {
                  if (value) {
                    _repeatDays.add(weekday);
                  } else {
                    _repeatDays.remove(weekday);
                  }
                }),
              );
            }),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: const Text('Sound'),
              subtitle: Text(_sound.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickSound,
            ),
          ),
          const SizedBox(height: 20),
          Text('Activity to stop the alarm', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "You'll need to open the camera and complete this before the alarm stops.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(preset.icon, color: Colors.deepPurpleAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _activityLabel,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Target: ', style: Theme.of(context).textTheme.bodyMedium),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _targetReps > 1 ? () => setState(() => _targetReps--) : null,
                      ),
                      Text(
                        '$_targetReps ${preset.unitLabel}',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() => _targetReps++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickActivityManually,
                          icon: const Icon(Icons.list_outlined),
                          label: const Text('Pick Manually'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickActivityViaCamera,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Set via Camera'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickSavedActivity,
                      icon: const Icon(Icons.bookmark_outline),
                      label: const Text('Choose a Saved Activity'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
