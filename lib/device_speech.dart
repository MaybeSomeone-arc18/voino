import 'package:speech_to_text/speech_to_text.dart';

import 'logic.dart';

/// Native (non-web) device recognizer setup: initialization, the locales the
/// recognizer reports, and the user's listening-language choice resolved
/// against them. Platform or plugin failures degrade to "not ready" or
/// "system default" instead of throwing.
class DeviceSpeech {
  DeviceSpeech(this.speech);
  final SpeechToText speech;

  bool ready = false;
  List<String> availableLocales = const [];

  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
  }) async {
    try {
      ready = await speech.initialize(onError: onError, onStatus: onStatus);
    } catch (_) {
      ready = false;
    }
    availableLocales = const [];
    if (ready) {
      try {
        final locales = await speech.locales();
        availableLocales = locales.map((l) => l.localeId).toList();
      } catch (_) {
        availableLocales = const [];
      }
    }
    return ready;
  }

  /// The locale to request for the next listen session, or null to keep the
  /// recognizer's system default. [choice] is a value from
  /// [kSpeechLangChoices].
  String? localeIdFor(String choice) =>
      resolveSpeechLocale(choice, availableLocales);
}
