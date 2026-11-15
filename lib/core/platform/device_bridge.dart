import 'package:flutter/services.dart';

/// Platform channel bridge to Android system UI features (speech input, notifications).
class DeviceBridge {
  const DeviceBridge._();

  static const MethodChannel _channel = MethodChannel('app.starfilm.android/launcher');

  static String toSpeechLocaleTag(String lang) {
    switch (lang) {
      case 'ru':
        return 'ru-RU';
      case 'en':
        return 'en-US';
      default:
        return 'uk-UA';
    }
  }

  /// Launches Android's system speech recognizer UI and returns recognized text,
  /// empty string if cancelled, or null if speech recognition is unavailable.
  static Future<String?> startVoiceInput({
    required String languageTag,
    String prompt = '',
  }) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'startVoiceInput',
        {
          'language': languageTag,
          if (prompt.isNotEmpty) 'prompt': prompt,
        },
      );
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> showReleaseNotification({
    required String title,
    required String body,
    int notifyId = 7101,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'showReleaseNotification',
        {
          'title': title,
          'body': body,
          'notifyId': notifyId,
        },
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
