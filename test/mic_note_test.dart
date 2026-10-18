import 'package:flutter_test/flutter_test.dart';
import 'package:voino/main.dart';

void main() {
  test('friendlyMicNote maps mic failures to plain words', () {
    expect(
      friendlyMicNote(
        'Speech stopped: error_not_allowed. Tap to try again or type instead.',
      ),
      contains('Microphone is blocked'),
    );
    expect(
      friendlyMicNote('NotAllowedError: Permission denied'),
      contains('Microphone is blocked'),
    );
    expect(
      friendlyMicNote('Microphone is blocked. Allow it for this site.'),
      contains('Microphone is blocked'),
    );
    expect(
      friendlyMicNote('error_audio_capture'),
      contains('No microphone answered'),
    );
    expect(
      friendlyMicNote('microphone_unavailable'),
      contains('No microphone answered'),
    );
    // Normal status lines pass through untouched.
    expect(
      friendlyMicNote('Listening · tap to stop'),
      'Listening · tap to stop',
    );
  });
}
