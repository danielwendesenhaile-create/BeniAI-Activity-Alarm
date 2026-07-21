import 'package:flutter/material.dart';

import '../../../models/activity_model.dart';

class ActivityPickerResult {
  final ActivityPreset preset;
  final String? customLabel;

  const ActivityPickerResult({required this.preset, this.customLabel});
}

/// Bottom sheet for manually choosing an [ActivityPreset] (the alternative
/// to the camera-based auto-detect flow).
Future<ActivityPickerResult?> showActivityPickerSheet(
  BuildContext context, {
  ActivityType? current,
}) {
  return showModalBottomSheet<ActivityPickerResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ActivityPickerContent(current: current),
  );
}

class _ActivityPickerContent extends StatefulWidget {
  const _ActivityPickerContent({this.current});

  final ActivityType? current;

  @override
  State<_ActivityPickerContent> createState() => _ActivityPickerContentState();
}

class _ActivityPickerContentState extends State<_ActivityPickerContent> {
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose an activity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...ActivityPreset.all.map((preset) {
            final isCustom = preset.type == ActivityType.custom;
            return Card(
              child: ListTile(
                leading: Icon(preset.icon, color: Colors.deepPurpleAccent),
                title: Text(preset.label),
                subtitle: Text(preset.description),
                onTap: isCustom
                    ? null
                    : () => Navigator.of(context).pop(ActivityPickerResult(preset: preset)),
              ),
            );
          }),
          const SizedBox(height: 8),
          TextField(
            controller: _customController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Or describe a custom activity',
              hintText: 'e.g. "Make your bed"',
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _customController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                    ActivityPickerResult(
                      preset: ActivityPreset.byType(ActivityType.custom),
                      customLabel: _customController.text.trim(),
                    ),
                  ),
            child: const Text('Use Custom Activity'),
          ),
        ],
      ),
    );
  }
}
