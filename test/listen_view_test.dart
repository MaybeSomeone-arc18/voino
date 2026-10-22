import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/main.dart';

// SIMULATED RENDERING on the test framework, not a real phone. The listen
// view's action row must wrap instead of overflowing at narrow width with
// large text. (Ported from the review branch; golden images were dropped
// because baselines are not kept in the repo.)
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

  testWidgets('listen view fits 360 width at text scale 2.0 without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: const Home(),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The mocked recognizer reports unavailable, so the type-instead hint shows;
    // what matters here is that nothing overflowed at 360px with 2x text.
    expect(tester.takeException(), isNull);
    expect(find.text('Speech unavailable · type instead'), findsOneWidget);
  });
}
