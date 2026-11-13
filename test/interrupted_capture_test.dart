import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/main.dart';

// SIMULATED RENDERING on the test framework, not a real phone. Verifies the
// interrupted-capture marker: a draft persisted while a capture was still
// open (crash, kill, power loss) restores WITH the warning and clears the
// flag so it warns once; a cleanly stopped draft restores without it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, String> seedStore({required bool captureActive}) => {
    'voino_draft_v1': jsonEncode({
      'draftVersion': 1,
      'title': 'Standup',
      'transcript': 'we discussed the launch plan',
      'summary': '',
      'source': '',
      'lastSource': '',
      'cards': <dynamic>[],
      'captureActive': captureActive,
    }),
  };

  setUp(() {
    const speech = MethodChannel('plugin.csdcorp.com/speech_to_text');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speech, (call) async {
          if (call.method == 'initialize') return false;
          return null;
        });
  });

  Future<TestFlutterSecureStoragePlatform> pumpHome(
    WidgetTester tester,
    Map<String, String> store,
  ) async {
    final platform = TestFlutterSecureStoragePlatform(store);
    FlutterSecureStoragePlatform.instance = platform;
    await tester.pumpWidget(const MaterialApp(home: Home()));
    await tester.pumpAndSettle();
    return platform;
  }

  testWidgets(
    'draft restored from an open capture warns that recent speech may be missing, once',
    (tester) async {
      final platform = await pumpHome(tester, seedStore(captureActive: true));

      expect(find.textContaining('ended unexpectedly'), findsOneWidget);
      expect(
        find.textContaining('most recent speech may be missing'),
        findsOneWidget,
      );

      // The restored content survived and the flag was cleared in storage
      // immediately, so a later reload does not warn about the same crash.
      final persisted =
          jsonDecode(platform.data['voino_draft_v1']!) as Map<String, dynamic>;
      expect(persisted['captureActive'], isFalse);
      expect(persisted['transcript'], 'we discussed the launch plan');

      // Dismissing hides the marker without touching the note.
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('ended unexpectedly'), findsNothing);
      final afterDismiss =
          jsonDecode(platform.data['voino_draft_v1']!) as Map<String, dynamic>;
      expect(afterDismiss['transcript'], 'we discussed the launch plan');
    },
  );

  testWidgets('cleanly stopped draft restores without the warning', (
    tester,
  ) async {
    final platform = await pumpHome(tester, seedStore(captureActive: false));
    expect(find.textContaining('ended unexpectedly'), findsNothing);
    final persisted =
        jsonDecode(platform.data['voino_draft_v1']!) as Map<String, dynamic>;
    expect(persisted['transcript'], 'we discussed the launch plan');
  });

  testWidgets('draft without the flag (older saves) restores without the warning', (
    tester,
  ) async {
    final store = seedStore(captureActive: false)
      ..['voino_draft_v1'] = jsonEncode({
        'draftVersion': 1,
        'title': 'Old save',
        'transcript': 'from before the flag existed',
        'summary': '',
        'source': '',
        'lastSource': '',
        'cards': <dynamic>[],
      });
    final platform = await pumpHome(tester, store);
    expect(find.textContaining('ended unexpectedly'), findsNothing);
    final persisted =
        jsonDecode(platform.data['voino_draft_v1']!) as Map<String, dynamic>;
    expect(persisted['transcript'], 'from before the flag existed');
  });
}
