import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/logic.dart';
import 'package:voino/minimal_notes.dart';

void main() {
  testWidgets(
    'hides empty sections and duplicate transcript; controls stay available',
    (t) async {
      var file = '';
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MinimalNotes(
                note: Note('New note', [], [
                  'Prepare the event.',
                ], 'Prepare the event.'),
                source: 'Rule-based extract',
                capture: const Text('EDITABLE TRANSCRIPT'),
                busy: false,
                onCopy: () {},
                onBoard: () {},
                onFile: (v) => file = v,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Key points'), findsNothing);
      expect(find.text('Things to do'), findsOneWidget);
      expect(find.text('Prepare the event.'), findsOneWidget);
      expect(find.text('Original transcript'), findsNothing);
      expect(find.text('EDITABLE TRANSCRIPT').hitTestable(), findsNothing);
      await t.tap(find.text('Transcript'));
      await t.pumpAndSettle();
      expect(find.text('EDITABLE TRANSCRIPT').hitTestable(), findsOneWidget);
      await t.tap(find.byTooltip('Board files'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save board JSON'));
      await t.pumpAndSettle();
      expect(file, 'save');
      expect(t.takeException(), isNull);
    },
  );
}
