import 'package:flutter/material.dart';

import '../../../models/activity_model.dart';

class ActivityPickerResult {
  final ActivityPreset preset;

  const ActivityPickerResult({required this.preset});
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
    builder: (context) => const _ActivityPickerContent(),
  );
}

class _ActivityPickerContent extends StatelessWidget {
  const _ActivityPickerContent();

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
            return Card(
              child: ListTile(
                leading: Icon(preset.icon, color: Colors.deepPurpleAccent),
                title: Text(preset.label),
                subtitle: Text(preset.description),
                onTap: () => Navigator.of(context).pop(ActivityPickerResult(preset: preset)),
              ),
            );
          }),
        ],
      ),
    );
  }
}
