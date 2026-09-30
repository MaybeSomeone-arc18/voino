import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/live_transcript.dart';

void main() {
  testWidgets('shows a waiting state then partial and accumulating words', (t) async {
    Future<void> show(String words) => t.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: LiveTranscript(text: words))),
    ));
    await show('');
    expect(find.text('LIVE TRANSCRIPT'), findsOneWidget);
    expect(find.textContaining('Waiting for words'), findsOneWidget);
    await show('Plants use');
    expect(find.text('Plants use'), findsOneWidget);
    await show('Plants use sunlight to make energy. Remember the worksheet.');
    expect(find.textContaining('Remember the worksheet.'), findsOneWidget);
    expect(find.textContaining('Waiting for words'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('long text stays bounded on a phone and follows the newest words', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Padding(
      padding: const EdgeInsets.all(24),
      child: LiveTranscript(text: List.filled(100, 'Meeting notes.').join(' ')),
    ))));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(LiveTranscript)).width, 342);
    final scroll = t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scroll.reverse, isTrue);
    expect(t.takeException(), isNull);
  });
}
