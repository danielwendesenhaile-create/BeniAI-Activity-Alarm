import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:superwallkit_flutter/superwallkit_flutter.dart';

import '../config/env_config.dart';

/// Wraps the Superwall SDK: configuration, identity, and paywall
/// presentation for gating premium features (extra alarms, custom
/// activities, etc.).
class PaywallService {
  final _subscriptionStatusController = StreamController<bool>.broadcast(sync: true);

  _AppSuperwallDelegate? _delegate;
  bool _configured = false;

  /// Emits `true` whenever the user's subscription becomes active.
  Stream<bool> get isSubscribedStream => _subscriptionStatusController.stream;

  Future<void> init() async {
    final apiKey = Platform.isIOS ? EnvConfig.superwallApiKeyIOS : EnvConfig.superwallApiKeyAndroid;

    if (apiKey.isEmpty) {
      debugPrint('PaywallService: Superwall API key not set, paywall disabled.');
      return;
    }

    Superwall.configure(apiKey);
    _delegate = _AppSuperwallDelegate(_subscriptionStatusController);
    Superwall.shared.setDelegate(_delegate);
    _configured = true;
  }

  Future<void> identify(String userId) async {
    if (!_configured) return;
    await Superwall.shared.identify(userId);
  }

  Future<void> reset() async {
    if (!_configured) return;
    await Superwall.shared.reset();
  }

  Future<bool> isSubscribed() async {
    if (!_configured) return false;
    final status = await Superwall.shared.getSubscriptionStatus();
    return status.isActive;
  }

  /// Presents the paywall for [placement] (defaults to the configured
  /// campaign trigger placement). [onUnlocked] fires when the user already
  /// has access or successfully purchases/restores.
  Future<void> presentPaywall({String? placement, required VoidCallback onUnlocked}) async {
    if (!_configured) {
      // No Superwall key configured (e.g. local dev) - don't block the user.
      onUnlocked();
      return;
    }

    await Superwall.shared.registerPlacement(
      placement ?? EnvConfig.superwallPaywallPlacement,
      feature: onUnlocked,
    );
  }

  void dispose() {
    _subscriptionStatusController.close();
  }
}

class _AppSuperwallDelegate extends SuperwallDelegate {
  _AppSuperwallDelegate(this._controller);

  final StreamController<bool> _controller;

  @override
  void subscriptionStatusDidChange(SubscriptionStatus newValue) {
    _controller.add(newValue.isActive);
  }

  @override
  void handleSuperwallEvent(SuperwallEventInfo eventInfo) {}

  @override
  void handleCustomPaywallAction(String name) {}

  @override
  void willDismissPaywall(PaywallInfo paywallInfo) {}

  @override
  void willPresentPaywall(PaywallInfo paywallInfo) {}

  @override
  void didDismissPaywall(PaywallInfo paywallInfo) {}

  @override
  void didPresentPaywall(PaywallInfo paywallInfo) {}

  @override
  void paywallWillOpenURL(Uri url) {}

  @override
  void paywallWillOpenDeepLink(Uri url) {}

  @override
  void handleLog(
    String level,
    String scope,
    String? message,
    Map<dynamic, dynamic>? info,
    String? error,
  ) {}

  @override
  void handleSuperwallDeepLink(
    Uri fullURL,
    List<String> pathComponents,
    Map<String, String> queryParameters,
  ) {}
}
