import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/board.dart';
import 'package:voino/board_controller.dart';
import 'package:voino/board_view.dart';

void main() {
  Future<BoardController> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1000, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = BoardController()
      ..replace(
        BoardData(
          [CardModel('a', 'idea', 'First note', 60, 60, 'sand')],
          [],
          [ShapeModel('box', const Rect.fromLTWH(400, 80, 200, 120))],
        ),
      );
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
    return c;
  }

  testWidgets(
    'double-click a card writes in place, no dialog; Escape keeps the text',
    (t) async {
      final c = await pump(t);
      await t.tap(find.text('First note'));
      await t.pump(const Duration(milliseconds: 60));
      await t.tap(find.text('First note'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Edited in place');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(c.cards.first.text, 'Edited in place');
      c.undo();
      expect(c.cards.first.text, 'First note');
    },
  );

  testWidgets(
    'T then tap on empty canvas creates free text; empty text is dropped',
    (t) async {
      final c = await pump(t);
      await t.tapAt(
        t.getTopLeft(find.byType(InteractiveViewer)) + const Offset(50, 400),
      );
      await t.pump(const Duration(milliseconds: 400));
      await t.sendKeyEvent(LogicalKeyboardKey.keyT);
      expect(c.tool, Tool.text);
      await t.tapAt(
        t.getTopLeft(find.byType(InteractiveViewer)) + const Offset(300, 400),
      );
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(c.shapes.last.type, 'text');
      await t.enterText(find.byType(TextField), 'Photosynthesis');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(
        c.shapes.where((s) => s.type == 'text').single.label,
        'Photosynthesis',
      );
      // Empty free text leaves nothing behind.
      final n = c.shapes.length;
      c.setTool(Tool.text);
      await t.tapAt(
        t.getTopLeft(find.byType(InteractiveViewer)) + const Offset(300, 500),
      );
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(c.shapes.length, n);
    },
  );

  testWidgets('typing letters while writing does not trigger tool shortcuts', (
    t,
  ) async {
    final c = await pump(t);
    c.setTool(Tool.text);
    await t.tapAt(
      t.getTopLeft(find.byType(InteractiveViewer)) + const Offset(300, 400),
    );
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'rota');
    await t.pumpAndSettle();
    expect(c.tool, Tool.select);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Enter edits the selected card and ? lists shortcuts', (t) async {
    final c = await pump(t);
    c.select(c.cards.first);
    await t.pumpAndSettle();
    await t.tapAt(
      t.getTopLeft(find.byType(InteractiveViewer)) + const Offset(300, 450),
    );
    await t.pump(const Duration(milliseconds: 400));
    c.select(c.cards.first);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Shortcuts (?)'));
    await t.pumpAndSettle();
    expect(find.text('Board shortcuts'), findsOneWidget);
  });
}
