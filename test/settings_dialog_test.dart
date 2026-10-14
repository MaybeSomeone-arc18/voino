import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/main.dart';

// SIMULATED RENDERING on the test framework, not a real phone. Verifies
// layout/readability of the native Settings dialog only.
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

  for (final scale in [1.0, 2.0]) {
    testWidgets('native Settings dialog renders at 360 width, text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            // builder so the scale also covers the dialog route, which sits
            // above home in the navigator overlay.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const Home(),
          ),
        ),
      );
      // Bounded pumps: the home screen keeps live autosave/session timers,
      // so pumpAndSettle would never settle.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byIcon(Icons.tune));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Listening language'), findsOneWidget);
      expect(find.text('Phone default'), findsOneWidget);

      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/settings-dialog-360-scale-$scale.png'),
      );
    });
  }
}
