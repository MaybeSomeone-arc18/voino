import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/board.dart';
import 'package:voino/board_controller.dart';
import 'package:voino/board_view.dart';
import 'package:voino/logic.dart';

const lecture = 'Photosynthesis means plants use sunlight to make energy. '
    'Photosynthesis happens in the chloroplast of plant cells. '
    'Chlorophyll absorbs sunlight and starts photosynthesis. '
    'Cellular respiration releases stored energy in mitochondria. '
    'Mitochondria produce energy for the cell. '
    'Remember to submit the biology worksheet Friday.';

Future<BoardController> pumpBoard(WidgetTester t) async {
  t.view.physicalSize = const Size(1000, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final c = BoardController()..replace(buildBoard(makeNotes(lecture, 'Bio')));
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: BoardPanel(controller: c, onSave: () {}, onOpen: () {}))),
  ));
  await t.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('dragging a card moves it, marks the board edited and can be undone', (t) async {
    final c = await pumpBoard(t);
    final card = c.cards.firstWhere((k) => k.type == 'point');
    final before = Offset(card.x, card.y);
    await t.drag(find.text(card.text).first, const Offset(60, 40));
    await t.pumpAndSettle();
    expect(card.x, greaterThan(before.dx));
    expect(card.y, greaterThan(before.dy));
    expect(c.edited, isTrue);
    expect(c.canUndo, isTrue);
    c.undo();
    final restored = c.cards.firstWhere((k) => k.id == card.id);
    expect(Offset(restored.x, restored.y), before);
  });

  testWidgets('box tool draws a new shape on empty canvas', (t) async {
    final c = await pumpBoard(t);
    final n = c.shapes.length;
    await t.tap(find.text('Draw box'));
    await t.pumpAndSettle();
    expect(c.tool, Tool.box);
    final origin = t.getTopLeft(find.byType(InteractiveViewer)) + const Offset(8, 8);
    await t.dragFrom(origin, const Offset(140, 100));
    await t.pumpAndSettle();
    expect(c.shapes.length, n + 1);
    expect(c.shapes.last.type, 'box');
    expect(c.tool, Tool.select); // returns to select after drawing
    expect(identical(c.selected, c.shapes.last), isTrue);
  });

  testWidgets('selecting a card then Delete removes it and its arrows', (t) async {
    final c = await pumpBoard(t);
    final card = c.cards.firstWhere((k) => k.id == 'p0');
    expect(c.links.any((l) => l.from == card.id || l.to == card.id), isTrue);
    await t.tap(find.text(card.text).first);
    await t.pump(const Duration(milliseconds: 400)); // single-tap waits out the double-tap window
    await t.pumpAndSettle();
    expect(identical(c.selected, card), isTrue);
    await t.tap(find.text('Delete selected'));
    await t.pumpAndSettle();
    expect(c.cards.any((k) => k.id == card.id), isFalse);
    expect(c.links.any((l) => l.from == card.id || l.to == card.id), isFalse);
    c.undo();
    expect(c.cards.any((k) => k.id == card.id), isTrue);
  });

  testWidgets('color button cycles the card color', (t) async {
    final c = await pumpBoard(t);
    final card = c.cards.firstWhere((k) => k.type == 'point');
    final start = card.color;
    final icons = find.descendant(of: find.ancestor(of: find.text(card.text).first, matching: find.byType(Column)).first, matching: find.byIcon(Icons.contrast));
    await t.tap(icons.first);
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(card.color, isNot(start));
  });

  testWidgets('connect tool links two cards with an arrow', (t) async {
    final c = await pumpBoard(t);
    final a = c.cards.firstWhere((k) => k.id == 'p0'), b = c.cards.firstWhere((k) => k.type == 'action');
    final n = c.links.length;
    await t.tap(find.text('Connect two cards'));
    await t.pumpAndSettle();
    await t.tap(find.text(a.text).first);
    await t.pumpAndSettle();
    expect(c.arrowFrom, a.id);
    await t.tap(find.text(b.text).first);
    await t.pumpAndSettle();
    expect(c.links.length, n + 1);
    expect(c.links.last.from, a.id);
    expect(c.links.last.to, b.id);
  });

  testWidgets('add a note puts an editable idea card on the board', (t) async {
    final c = await pumpBoard(t);
    final n = c.cards.length;
    await t.tap(find.text('+ Add a note'));
    await t.pumpAndSettle();
    expect(c.cards.length, n + 1);
    expect(c.cards.last.type, 'idea');
    expect(identical(c.selected, c.cards.last), isTrue);
  });
}
