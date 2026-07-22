import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../models/activity_model.dart';
import '../../../models/activity_template_model.dart';
import '../../alarms/providers/alarm_providers.dart';
import '../../auth/providers/auth_providers.dart';

/// Bottom sheet listing the user's saved (recorded-and-named) activities,
/// for reuse on any future alarm without recording again.
Future<ActivityTemplate?> showSavedActivityPickerSheet(BuildContext context) {
  return showModalBottomSheet<ActivityTemplate>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _SavedActivityPickerContent(),
  );
}

class _SavedActivityPickerContent extends ConsumerWidget {
  const _SavedActivityPickerContent();

  Future<void> _delete(BuildContext context, WidgetRef ref, ActivityTemplate template) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref
        .read(firestoreRepositoryProvider)
        .deleteActivityTemplate(uid: uid, templateId: template.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(userActivityTemplatesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Saved activities', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Activities you recorded and named via "Set via Camera".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: templatesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('Could not load saved activities: $e'),
                ),
                data: (templates) {
                  if (templates.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        "You haven't saved any activities yet. Use \"Set via Camera\" and "
                        'name it to save it here for next time.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: templates.length,
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      final preset = ActivityPreset.byType(template.activityType);
                      final imageBase64 = template.referenceImageBase64;
                      return Card(
                        child: ListTile(
                          leading: imageBase64 != null && imageBase64.isNotEmpty
                              ? CircleAvatar(
                                  backgroundImage: MemoryImage(base64Decode(imageBase64)),
                                )
                              : Icon(preset.icon, color: Colors.deepPurpleAccent),
                          title: Text(template.name),
                          subtitle: Text('${template.defaultTarget} ${preset.unitLabel}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, ref, template),
                          ),
                          onTap: () => Navigator.of(context).pop(template),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
