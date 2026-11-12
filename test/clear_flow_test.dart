import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/main.dart';

// SIMULATED RENDERING on the test framework, not a real phone. Drives the real
// Home UI: type a transcript, make local notes, Clear (archives the note),
// then verify opening a recent note keeps the note it replaces in the list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      {},
    );
    const speech = MethodChannel('plugin.csdcorp.com/speech_to_text');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speech, (call) async {
          if (call.method == 'initialize') return false;
          return null;
        });
  });

  test('clearConfirmText warns before evicting the oldest saved note', () {
    final warn = clearConfirmText(willEvict: true, oldestTitle: 'Old sync');
    expect(warn, contains('Old sync'));
    expect(warn, contains('will be removed'));
    expect(
      clearConfirmText(willEvict: false),
      isNot(contains('will be removed')),
    );
  });

  Future<void> typeNote(
    WidgetTester tester,
    String name,
    String transcript,
  ) async {
    final typeInstead = find.text('Type instead');
    if (typeInstead.evaluate().isNotEmpty) {
      await tester.tap(typeInstead.first);
      await tester.pumpAndSettle();
    }
    final field = find.widgetWithText(
      TextField,
      'What Voino heard (you can fix mistakes)',
    );
    if (field.evaluate().isEmpty) {
      await tester.tap(find.text('Transcript'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.widgetWithText(TextField, 'Give it a name'),
      name,
    );
    await tester.enterText(field, transcript);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make board'));
    await tester.pumpAndSettle();
    // If a consent dialog for cloud processing appears, decline it so the
    // on-device extractor runs.
    final cancel = find.text('Cancel');
    if (cancel.evaluate().isNotEmpty) {
      await tester.tap(cancel.first);
      await tester.pumpAndSettle();
    }
  }

  Future<void> openRecent(WidgetTester tester) async {
    final typeInstead = find.text('Type instead');
    if (typeInstead.evaluate().isNotEmpty) {
      await tester.tap(typeInstead.first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Board files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent notes on this device').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Clear archives; opening a recent note keeps the replaced one',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: Home()));
      await tester.pumpAndSettle();

      await typeNote(
        tester,
        'Launch planning sync',
        'We need to finish the pitch deck by Thursday. '
            'Priya said she will draft the market slide tonight. '
            'The team decided to launch the beta next Monday.',
      );

      expect(find.text('Rule-based extract'), findsOneWidget);
      expect(
        find.text('Priya said she will draft the market slide tonight.'),
        findsOneWidget,
      );

      // Clear asks for confirmation, then archives the note.
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Clear everything: transcript, notes, board'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Rule-based extract'), findsNothing);

      // A second discussion becomes the current note.
      await typeNote(
        tester,
        'Second sync',
        'Ravi will own the signup metrics dashboard. '
            'The team agreed to review pricing before the beta launch.',
      );
      expect(find.text('Rule-based extract'), findsOneWidget);

      // Opening the first note from Recent notes must not lose the second:
      // it is archived automatically, and no duplicate of the opened note
      // appears.
      await openRecent(tester);
      await tester.tap(find.text('Launch planning sync').last);
      await tester.pumpAndSettle();

      await openRecent(tester);
      expect(find.text('Second sync'), findsOneWidget);
      expect(find.text('Launch planning sync'), findsWidgets);
    },
  );
}
