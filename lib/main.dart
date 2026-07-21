import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/service_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env present yet - services fall back to a disabled/no-op state
    // (see EnvConfig) rather than crashing the app.
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final container = ProviderContainer();
  await container.read(alarmSchedulerServiceProvider).init();
  await container.read(analyticsServiceProvider).init();
  await container.read(paywallServiceProvider).init();

  runApp(UncontrolledProviderScope(container: container, child: const BeniAIApp()));
}

class BeniAIApp extends ConsumerStatefulWidget {
  const BeniAIApp({super.key});

  @override
  ConsumerState<BeniAIApp> createState() => _BeniAIAppState();
}

class _BeniAIAppState extends ConsumerState<BeniAIApp> {
  StreamSubscription? _ringingSubscription;
  final Set<int> _handledAlarmIds = {};

  @override
  void initState() {
    super.initState();
    _listenForRingingAlarms();
  }

  void _listenForRingingAlarms() {
    final scheduler = ref.read(alarmSchedulerServiceProvider);
    _ringingSubscription = scheduler.ringingStream.listen((alarmSet) {
      for (final settings in alarmSet.alarms) {
        if (_handledAlarmIds.contains(settings.id)) continue;
        _handledAlarmIds.add(settings.id);

        final alarmId = settings.payload;
        if (alarmId == null || alarmId.isEmpty) continue;

        final router = ref.read(appRouterProvider);
        router.push('/alarm/$alarmId/ring');
      }
    });
  }

  @override
  void dispose() {
    _ringingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'BeniAI Activity Alarm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
