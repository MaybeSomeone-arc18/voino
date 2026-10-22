import 'package:flutter_test/flutter_test.dart';
import 'package:voino/logic.dart';

void main() {
  group('resolveSpeechLocale', () {
    test('auto keeps the system default', () {
      expect(resolveSpeechLocale('auto', ['en_US', 'hi_IN']), isNull);
      expect(resolveSpeechLocale('auto', []), isNull);
    });
    test('unknown or stale stored choices fall back to system default', () {
      expect(resolveSpeechLocale('ta_IN', ['ta_IN']), isNull);
      expect(resolveSpeechLocale('', ['hi_IN']), isNull);
    });
    test('selected locale is used when the device offers it', () {
      expect(resolveSpeechLocale('hi_IN', ['en_US', 'hi_IN']), 'hi_IN');
      expect(resolveSpeechLocale('en_IN', ['en_IN', 'hi_IN']), 'en_IN');
    });
    test('dash-separated device ids match, returning the platform id', () {
      expect(resolveSpeechLocale('hi_IN', ['hi-IN']), 'hi-IN');
    });
    test('language-only fallback when the exact region id is absent', () {
      expect(resolveSpeechLocale('hi_IN', ['en_US', 'hi']), 'hi');
    });
    test('unavailable language keeps the system default', () {
      expect(resolveSpeechLocale('hi_IN', ['en_US', 'en_GB']), isNull);
      expect(resolveSpeechLocale('en_IN', []), isNull);
    });
    test('a different region of the chosen language is the nearest fallback', () {
      expect(resolveSpeechLocale('en_IN', ['en_US', 'en_GB']), 'en_US');
    });

    test('Devanagari detector catches Hindi, not English or romanized Hinglish', () {
      expect(hasDevanagari('aaj \u0915\u094d\u092f\u093e \u0939\u0941\u0906'), isTrue);
      expect(hasDevanagari('\u0928\u092e\u0938\u094d\u0924\u0947'), isTrue);
      expect(hasDevanagari('kal meeting hai'), isFalse);
      expect(hasDevanagari('plain english words'), isFalse);
      expect(hasDevanagari(''), isFalse);
    });
    test('cloud default locale prefers en_IN when the browser offers it', () {
      expect(defaultCloudLocale(['en_US', 'en_IN', 'hi_IN']), 'en_IN');
      expect(defaultCloudLocale(['hi-IN', 'en-IN']), 'en-IN');
      expect(defaultCloudLocale(['en_US', 'en_GB']), 'en_US');
      expect(defaultCloudLocale(['hi_IN']), isNull);
      expect(defaultCloudLocale([]), isNull);
    });
  });
}
