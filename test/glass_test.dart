import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/glass.dart';

void main() {
  testWidgets('glass button taps and shows its label', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          Expanded(child: GlassButton(label: 'Clear', onPressed: () => taps++)),
          Expanded(child: GlassButton(label: 'Make board', primary: true, onPressed: () => taps += 10)),
        ]),
      ),
    ));
    expect(find.text('Clear'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.tap(find.text('Make board'));
    expect(taps, 11);
  });

  testWidgets('disabled glass button ignores taps', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GlassButton(label: 'Working...', onPressed: null)),
    ));
    await tester.tap(find.text('Working...'));
    await tester.pump();
    expect(find.text('Working...'), findsOneWidget);
  });
}
