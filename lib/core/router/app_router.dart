import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/alarms/screens/alarm_edit_screen.dart';
import '../../features/alarm_ring/screens/alarm_ring_screen.dart';
import '../../features/alarm_ring/screens/activity_verification_screen.dart';
import '../../features/auth/screens/auth_gate.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Global navigator key so services (e.g. the alarm-ring listener in
/// main.dart) can push routes without a [BuildContext].
final rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const newAlarm = '/alarm/new';
  static String editAlarm(String id) => '/alarm/$id/edit';
  static String ringAlarm(String id) => '/alarm/$id/ring';
  static String verifyAlarm(String id) => '/alarm/$id/verify';
  static const settings = '/settings';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (context, state) => const AuthGate()),
      GoRoute(
        path: AppRoutes.newAlarm,
        builder: (context, state) => const AlarmEditScreen(alarmId: null),
      ),
      GoRoute(
        path: '/alarm/:id/edit',
        builder: (context, state) => AlarmEditScreen(alarmId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/alarm/:id/ring',
        builder: (context, state) => AlarmRingScreen(alarmId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/alarm/:id/verify',
        builder: (context, state) =>
            ActivityVerificationScreen(alarmId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
    ],
  );
});
