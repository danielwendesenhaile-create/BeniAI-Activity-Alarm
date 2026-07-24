import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place to read secrets/config loaded from `.env` at startup.
/// See `.env.example` for the full list of keys and where to get them.
class EnvConfig {
  EnvConfig._();

  static String get mixpanelToken => dotenv.env['MIXPANEL_TOKEN'] ?? '';

  static String get superwallApiKeyIOS => dotenv.env['SUPERWALL_API_KEY_IOS'] ?? '';

  static String get superwallApiKeyAndroid => dotenv.env['SUPERWALL_API_KEY_ANDROID'] ?? '';

  static String get superwallPaywallPlacement =>
      dotenv.env['SUPERWALL_PAYWALL_PLACEMENT'] ?? 'campaign_trigger';

  static bool get isConfigured =>
      mixpanelToken.isNotEmpty && (superwallApiKeyIOS.isNotEmpty || superwallApiKeyAndroid.isNotEmpty);
}
