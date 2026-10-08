import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/engine_switch.dart';

void main() {
  testWidgets('switch changes engine, animates and updates the hint', (tester) async {
    var engine = 'device';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => EngineSwitch(
            engine: engine,
            ink: const Color(0xFF2B2A28),
            paper: const Color(0xFFF4EEE1),
            onChanged: (v) => setState(() => engine = v),
          ),
        ),
      ),
    ));
    expect(find.text('Cloud: starts instantly, needs internet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('engine-whisper')));
    await tester.pump(const Duration(milliseconds: 100)); // mid-animation
    await tester.pumpAndSettle();
    expect(engine, 'whisper');
    expect(find.text('On-device: private, no internet after the first download'), findsOneWidget);
  });

  testWidgets('third option selects gemini and shows its hint', (tester) async {
    var engine = 'device';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => EngineSwitch(
            engine: engine,
            ink: const Color(0xFF2B2A28),
            paper: const Color(0xFFF4EEE1),
            onChanged: (v) => setState(() => engine = v),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('engine-gemini')));
    await tester.pumpAndSettle();
    expect(engine, 'gemini');
    expect(find.textContaining('Gemini: stronger'), findsOneWidget);
  });

  testWidgets('disabled switch ignores taps', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EngineSwitch(
          engine: 'device',
          enabled: false,
          ink: Colors.black,
          paper: Colors.white,
          onChanged: (_) => calls++,
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('engine-whisper')));
    await tester.pump();
    expect(calls, 0);
  });
}
