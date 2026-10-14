import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/main.dart';

// SIMULATED RENDERING on the test framework, not a real phone.
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

  testWidgets('listen view action row fits 360 width at text scale 2.0', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: const Home(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // An overflow exception, if any, is captured in the image as striped
    // markers; take it so capture proceeds (used for before/after evidence).
    tester.takeException();
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/listen-view-360-scale-2.0.png'),
    );
  });
}
