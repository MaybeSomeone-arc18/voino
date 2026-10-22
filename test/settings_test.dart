import 'package:flutter_test/flutter_test.dart';
import 'package:voino/settings.dart';

void main() {
  test(
    'save writes settings and consent without logging key contents',
    () async {
      final values = <String, String>{};
      final s = Settings(
        keys: ['local-key'],
        useAi: true,
        consented: true,
        write: (key, value) async {
          values[key] = value;
        },
      );
      await s.save();
      expect(values['gemini_keys'], 'local-key');
      expect(values['use_ai'], '1');
      expect(values['ai_consent'], '1');
      expect(values['proxy_consent'], '0');
    },
  );
  test('speech language choice persists with the save batch', () async {
    final values = <String, String>{};
    final s = Settings(
      speechLang: 'hi_IN',
      write: (key, value) async {
        values[key] = value;
      },
    );
    await s.save();
    expect(values['speech_lang'], 'hi_IN');
  });
  test('unknown stored speech language reads back as auto', () {
    expect(Settings.validLang('ta_IN'), 'auto');
    expect(Settings.validLang(null), 'auto');
    expect(Settings.validLang('en_IN'), 'en_IN');
  });
  test('storage failure is not swallowed as successful save', () async {
    final s = Settings(
      write: (_, __) async => throw StateError('storage unavailable'),
    );
    await expectLater(s.save(), throwsStateError);
  });
}
