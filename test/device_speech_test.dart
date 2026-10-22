import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:voino/device_speech.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mock({bool initResult = true, Object? initError, List<String>? locales, bool localesThrow = false}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize':
          if (initError != null) throw initError;
          return initResult;
        case 'locales':
          if (localesThrow) throw PlatformException(code: 'no_locales');
          return (locales ?? const <String>[]).map((id) => '$id: $id').toList();
        default:
          return null;
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  test('successful init exposes locales; choice resolves, auto stays default', () async {
    mock(locales: ['en_US', 'hi_IN']);
    final d = DeviceSpeech(SpeechToText.withMethodChannel());
    expect(await d.initialize(), isTrue);
    expect(d.ready, isTrue);
    expect(d.localeIdFor('auto'), isNull);
    expect(d.localeIdFor('hi_IN'), 'hi_IN');
    expect(d.localeIdFor('en_IN'), 'en_US'); // same language, nearest region
  });

  test('recognizer absent leaves ready false and every choice on default', () async {
    mock(initResult: false);
    final d = DeviceSpeech(SpeechToText.withMethodChannel());
    expect(await d.initialize(), isFalse);
    expect(d.ready, isFalse);
    expect(d.localeIdFor('hi_IN'), isNull);
  });

  test('plugin failure during init degrades instead of throwing', () async {
    mock(initError: PlatformException(code: 'no_plugin'));
    final d = DeviceSpeech(SpeechToText.withMethodChannel());
    expect(await d.initialize(), isFalse);
    expect(d.ready, isFalse);
  });

  test('locale query failure keeps recognizer usable on system default', () async {
    mock(localesThrow: true);
    final d = DeviceSpeech(SpeechToText.withMethodChannel());
    expect(await d.initialize(), isTrue);
    expect(d.localeIdFor('hi_IN'), isNull);
  });
}
