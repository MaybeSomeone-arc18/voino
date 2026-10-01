import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/board.dart';
import 'package:voino/board_controller.dart';
import 'package:voino/board_view.dart';

void main() {
  Future<BoardController> pump(WidgetTester t, {double width = 390}) async {
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = BoardController()
      ..replace(
        BoardData(
          [
            CardModel('a', 'idea', 'First note', 60, 60, 'sand'),
            CardModel('b', 'idea', 'Second note', 450, 60, 'mint'),
          ],
          [],
          [],
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
    'phone shows compact tools and preserves drawing and files in More',
    (t) async {
      await pump(t);
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Move'), findsOneWidget);
      expect(find.text('+ Note'), findsOneWidget);
      expect(find.text('Draw box'), findsNothing);
      expect(find.text('Save board .json'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
      await t.tap(find.byTooltip('More board tools'));
      await t.pumpAndSettle();
      expect(find.text('Draw box'), findsOneWidget);
      expect(find.text('Save board .json'), findsOneWidget);
      expect(find.text('Open board file'), findsOneWidget);
      await t.tap(find.text('Draw box'));
      await t.pumpAndSettle();
      expect(find.text('Board tools'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('Move drags the canvas without editing the note', (t) async {
    final c = await pump(t);
    final before = Offset(c.cards.first.x, c.cards.first.y);
    await t.tap(find.text('Move'));
    await t.pumpAndSettle();
    final viewer = t.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final matrix = viewer.transformationController!.value.clone();
    await t.drag(find.text('First note'), const Offset(45, 35));
    await t.pumpAndSettle();
    expect(Offset(c.cards.first.x, c.cards.first.y), before);
    expect(c.edited, isFalse);
    expect(viewer.transformationController!.value, isNot(matrix));
    await t.tap(find.text('Select'));
    await t.pumpAndSettle();
    await t.tap(find.text('First note'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Add while moving exits pan, selects new note, undo removes it', (
    t,
  ) async {
    final c = await pump(t);
    await t.tap(find.text('Move'));
    await t.pumpAndSettle();
    await t.tap(find.text('+ Note'));
    await t.pumpAndSettle();
    expect(c.cards.length, 3);
    expect(c.selected, same(c.cards.last));
    expect(find.text('Edit'), findsOneWidget);
    await t.tap(find.byTooltip('Undo'));
    await t.pumpAndSettle();
    expect(c.cards.length, 2);
  });

  testWidgets('320px and scaled text toolbar does not overflow', (t) async {
    await pump(t, width: 320);
    expect(t.takeException(), isNull);
  });
}
