import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/activity_model.dart';
import '../config/env_config.dart';

/// Result of asking OpenAI to identify what activity a camera frame,
/// captured during alarm setup, shows the user demonstrating.
class ActivityIdentification {
  final ActivityType type;
  final String label;
  final int suggestedTarget;
  final String reasoning;

  const ActivityIdentification({
    required this.type,
    required this.label,
    required this.suggestedTarget,
    required this.reasoning,
  });
}

/// Result of asking OpenAI to judge a single camera frame against the
/// activity the user is supposed to be doing.
class ActivityVisionCheck {
  final bool isPerformingActivity;
  final bool looksComplete;
  final String reasoning;

  const ActivityVisionCheck({
    required this.isPerformingActivity,
    required this.looksComplete,
    required this.reasoning,
  });

  factory ActivityVisionCheck.fallback(String reason) =>
      ActivityVisionCheck(isPerformingActivity: false, looksComplete: false, reasoning: reason);
}

/// Wraps OpenAI's Chat Completions API (with vision input) to spot-check
/// that the user is actually performing the activity shown to the camera.
///
/// Used as the fallback verifier for [ActivityType.custom] activities, and
/// as a periodic sanity-check alongside on-device pose detection in
/// [VerificationMode.hybrid].
class OpenAIService {
  OpenAIService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  Future<ActivityVisionCheck> verifyActivityFrame({
    required Uint8List jpegBytes,
    required String activityLabel,
    required int targetCount,
    required int currentCount,
    Uint8List? referenceJpegBytes,
  }) async {
    final apiKey = EnvConfig.openAiApiKey;
    if (apiKey.isEmpty) {
      return ActivityVisionCheck.fallback('OpenAI API key not configured.');
    }

    final base64Image = base64Encode(jpegBytes);
    final referenceBase64 = referenceJpegBytes != null ? base64Encode(referenceJpegBytes) : null;

    final prompt = referenceBase64 != null
        ? '''
You are a strict but encouraging fitness alarm-clock assistant. The FIRST
image below is a reference photo the user recorded of themselves
demonstrating "$activityLabel" when they set up this alarm. The SECOND image
is what the camera sees right now, while the alarm is ringing and they're
trying to stop it by performing that same activity ($targetCount total
reps/times, $currentCount counted so far).

Answer ONLY with compact JSON matching this shape, no prose, no markdown:
{"is_performing_activity": boolean, "looks_complete": boolean, "reasoning": "short reason"}

- is_performing_activity: true if the second image shows the person doing
  the same kind of activity/motion as the reference photo (or clearly just
  finished a rep of it) - compare posture and movement to the reference,
  not just whether someone is in frame.
- looks_complete: true only if it's plausible they've now done the full
  $targetCount, based on visible effort/fatigue cues. Default to false if
  unsure.
'''
        : '''
You are a strict but encouraging fitness alarm-clock assistant. Look at this
single camera frame of a user who set an alarm that only stops once they
perform: "$activityLabel" ($targetCount total reps/times, $currentCount
counted so far).

Answer ONLY with compact JSON matching this shape, no prose, no markdown:
{"is_performing_activity": boolean, "looks_complete": boolean, "reasoning": "short reason"}

- is_performing_activity: true if the person in frame is actively doing that
  activity right now (or clearly just finished a rep of it).
- looks_complete: true only if it's plausible they've now done the full
  $targetCount, based on visible effort/fatigue cues. Default to false if
  unsure.
''';

    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
      if (referenceBase64 != null)
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$referenceBase64'},
        },
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
      },
    ];

    final body = jsonEncode({
      'model': EnvConfig.openAiModel,
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'max_tokens': 200,
      'temperature': 0,
      'response_format': {'type': 'json_object'},
    });

    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return ActivityVisionCheck.fallback('OpenAI request failed (${response.statusCode}).');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final content = decoded['choices']?[0]?['message']?['content'] as String?;
      if (content == null) {
        return ActivityVisionCheck.fallback('Empty response from OpenAI.');
      }

      final parsed = jsonDecode(content) as Map<String, dynamic>;
      return ActivityVisionCheck(
        isPerformingActivity: parsed['is_performing_activity'] as bool? ?? false,
        looksComplete: parsed['looks_complete'] as bool? ?? false,
        reasoning: parsed['reasoning'] as String? ?? '',
      );
    } catch (e) {
      return ActivityVisionCheck.fallback('Vision check error: $e');
    }
  }

  /// Used during alarm setup: the user demonstrates the activity on camera
  /// and OpenAI vision identifies which built-in activity it best matches
  /// (or classifies it as custom), so the alarm can "set the activity"
  /// automatically instead of requiring a manual pick.
  ///
  /// Throws a [StateError] with a human-readable message on any failure
  /// (missing key, network error, bad response) instead of failing silently
  /// - callers should catch it and show `e` to the user so real failures
  /// are diagnosable instead of looking identical to "didn't recognize it".
  Future<ActivityIdentification> identifyActivity(Uint8List jpegBytes) async {
    final apiKey = EnvConfig.openAiApiKey;
    if (apiKey.isEmpty) {
      throw StateError("AI setup isn't configured (no OpenAI API key found).");
    }

    final base64Image = base64Encode(jpegBytes);
    const prompt = '''
Look at this camera frame of someone demonstrating a physical activity they
want an alarm-clock app to require of them each morning.

Answer ONLY with compact JSON, no prose, no markdown:
{"type": "squats" | "pushUps" | "jumpingJacks" | "custom", "label": "short activity name", "suggested_target": integer, "reasoning": "short reason"}

- type: pick "squats", "pushUps", or "jumpingJacks" if that's clearly what's
  shown; otherwise "custom".
- label: human readable name for the activity (e.g. "Squats", "Make the bed").
- suggested_target: a reasonable number of reps/times for a morning wake-up
  routine (e.g. 15-30 for squats/jumping jacks, 8-15 for push-ups, 1 for a
  one-off custom task).
''';

    final body = jsonEncode({
      'model': EnvConfig.openAiModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
            },
          ],
        },
      ],
      'max_tokens': 200,
      'temperature': 0,
      'response_format': {'type': 'json_object'},
    });

    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw StateError('OpenAI request failed (HTTP ${response.statusCode}).');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final content = decoded['choices']?[0]?['message']?['content'] as String?;
      if (content == null) {
        throw StateError('OpenAI returned an empty response.');
      }

      final parsed = jsonDecode(content) as Map<String, dynamic>;
      return ActivityIdentification(
        type: ActivityTypeJson.fromId(parsed['type'] as String? ?? 'custom'),
        label: parsed['label'] as String? ?? 'Activity',
        suggestedTarget: (parsed['suggested_target'] as num?)?.toInt() ?? 15,
        reasoning: parsed['reasoning'] as String? ?? '',
      );
    } on StateError {
      rethrow;
    } on TimeoutException {
      throw StateError('Timed out waiting for OpenAI - check your internet connection.');
    } catch (e) {
      throw StateError('OpenAI request error: $e');
    }
  }

  /// Generates a short motivational line shown while the user is mid-activity.
  Future<String> generateMotivationalLine(String activityLabel) async {
    final apiKey = EnvConfig.openAiApiKey;
    if (apiKey.isEmpty) return "Let's go! Keep going until you hit your target.";

    final body = jsonEncode({
      'model': EnvConfig.openAiModel,
      'messages': [
        {
          'role': 'user',
          'content':
              'Give one short (under 12 words), punchy, upbeat line to motivate '
              'someone mid-way through "$activityLabel" to wake themselves up. '
              'No emoji, no quotes.',
        },
      ],
      'max_tokens': 30,
      'temperature': 0.9,
    });

    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return "Let's go! Keep going until you hit your target.";
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final content = decoded['choices']?[0]?['message']?['content'] as String?;
      return (content ?? "Let's go! Keep going.").trim();
    } catch (_) {
      return "Let's go! Keep going until you hit your target.";
    }
  }

  void dispose() => _client.close();
}
