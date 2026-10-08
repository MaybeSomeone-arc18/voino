/// Non-web platforms: Whisper is not available (Android uses the device recognizer).
class WhisperEngine {
  static bool get supported => false;

  static Future<void> start({
    required void Function(String text) onText,
    required void Function(int percent) onProgress,
    required void Function(String message) onError,
    void Function(String partial)? onPartial,
  }) async =>
      throw UnsupportedError('Whisper is only available on web.');

  static void useCloud(bool on) {}

  static Future<void> stop() async {}
}
