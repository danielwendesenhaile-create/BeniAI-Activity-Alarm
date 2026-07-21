import 'package:flutter/foundation.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import '../config/env_config.dart';

/// Event name constants tracked throughout the app, kept in one place so
/// analysts and engineers agree on naming.
class AnalyticsEvents {
  AnalyticsEvents._();

  static const signUp = 'sign_up';
  static const signIn = 'sign_in';
  static const signOut = 'sign_out';

  static const alarmCreated = 'alarm_created';
  static const alarmUpdated = 'alarm_updated';
  static const alarmDeleted = 'alarm_deleted';
  static const alarmToggled = 'alarm_toggled';

  static const alarmRang = 'alarm_rang';
  static const activityVerificationStarted = 'activity_verification_started';
  static const activityRepCounted = 'activity_rep_counted';
  static const activityVerificationCompleted = 'activity_verification_completed';
  static const alarmDismissed = 'alarm_dismissed';
  static const alarmSnoozed = 'alarm_snoozed';

  static const paywallViewed = 'paywall_viewed';
  static const paywallDismissed = 'paywall_dismissed';
  static const subscriptionStarted = 'subscription_started';
}

/// Wraps the Mixpanel SDK. Call [init] once at startup before using any
/// other method.
class AnalyticsService {
  Mixpanel? _mixpanel;

  bool get isReady => _mixpanel != null;

  Future<void> init() async {
    final token = EnvConfig.mixpanelToken;
    if (token.isEmpty) {
      debugPrint('AnalyticsService: MIXPANEL_TOKEN not set, analytics disabled.');
      return;
    }
    _mixpanel = await Mixpanel.init(token, trackAutomaticEvents: true);
  }

  void identify(String userId) {
    _mixpanel?.identify(userId);
  }

  void setUserProperties(Map<String, dynamic> properties) {
    final people = _mixpanel?.getPeople();
    if (people == null) return;
    for (final entry in properties.entries) {
      people.set(entry.key, entry.value);
    }
  }

  void track(String event, [Map<String, dynamic>? properties]) {
    _mixpanel?.track(event, properties: properties);
  }

  void reset() {
    _mixpanel?.reset();
  }
}
