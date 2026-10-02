import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/board.dart';
import 'package:voino/board_controller.dart';
import 'package:voino/board_view.dart';

void main() {
  BoardController make() => BoardController()
    ..replace(
      BoardData([CardModel('a', 'idea', 'First note', 60, 60, 'sand')], [], []),
    );

  test('redo restores what undo removed, and a new edit clears redo', () {
    final c = make();
    c.addCard(const Offset(300, 300));
    expect(c.cards.length, 2);
    c.undo();
    expect(c.cards.length, 1);
    expect(c.canRedo, isTrue);
    c.redo();
    expect(c.cards.length, 2);
    expect(c.canRedo, isFalse);
    c.undo();
    c.addCard(const Offset(400, 400));
    expect(c.canRedo, isFalse);
  });

  test(
    'duplicate copies the selected card with an offset and selects the copy',
    () {
      final c = make();
      c.select(c.cards.first);
      c.duplicateSelected();
      expect(c.cards.length, 2);
      expect(c.cards.last.text, 'First note');
      expect(c.cards.last.x, 92);
      expect(identical(c.selected, c.cards.last), isTrue);
      c.undo();
      expect(c.cards.length, 1);
    },
  );

  testWidgets(
    'keyboard: R picks box, Escape returns to select, N adds a note',
    (t) async {
      t.view.physicalSize = const Size(1000, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = make();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BoardPanel(controller: c, onSave: () {}, onOpen: () {}),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tapAt(
        t.getTopLeft(find.byType(InteractiveViewer)) + const Offset(600, 300),
      );
      await t.pump(const Duration(milliseconds: 400));
      await t.sendKeyEvent(LogicalKeyboardKey.keyR);
      expect(c.tool, Tool.box);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(c.tool, Tool.select);
      await t.sendKeyEvent(LogicalKeyboardKey.keyN);
      await t.pumpAndSettle();
      expect(c.cards.length, 2);
    },
  );
}
