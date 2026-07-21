import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alarms/screens/alarm_list_screen.dart';
import '../providers/auth_providers.dart';
import 'login_screen.dart';

/// Root screen: shows a spinner while Firebase resolves the auth state,
/// then routes to [LoginScreen] or [AlarmListScreen].
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(body: Center(child: Text('Something went wrong: $error'))),
      data: (user) {
        if (user == null) return const LoginScreen();

        // Ensures the Firestore profile + analytics/paywall identity exist
        // for this signed-in user; a no-op after the first successful run.
        ref.watch(userBootstrapProvider);

        return const AlarmListScreen();
      },
    );
  }
}
