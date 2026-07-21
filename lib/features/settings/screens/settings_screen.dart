import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/services/analytics_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../../paywall/paywall_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(paywallServiceProvider).reset();
    ref.read(analyticsServiceProvider)
      ..track(AnalyticsEvents.signOut)
      ..reset();
    await ref.read(firebaseAuthServiceProvider).signOut();
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _manageSubscription(WidgetRef ref) async {
    await ref.read(paywallServiceProvider).presentPaywall(onUnlocked: () {});
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final isSubscribed = ref.watch(isSubscribedProvider).value ?? profile?.isPremium ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(profile?.email ?? ''),
              subtitle: Text(isSubscribed ? 'BeniAI Premium' : 'Free plan'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Manage subscription'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _manageSubscription(ref),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () => _signOut(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}
