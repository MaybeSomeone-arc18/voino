import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'board.dart';

enum Tool { select, box, circle, arrow }

/// State of the editable board: elements, current tool, selection and undo history.
class BoardController extends ChangeNotifier {
  List<CardModel> cards = [];
  List<Link> links = [];
  List<ShapeModel> shapes = [];
  bool edited = false;
  Tool tool = Tool.select;
  Object? selected; // CardModel | ShapeModel | Link
  String? arrowFrom; // first card chosen while the arrow tool is active
  int fitTick = 0; // bumped when the view should refit to the content
  final List<String> _undo = [];

  bool get isEmpty => cards.isEmpty && shapes.isEmpty;
  bool get canUndo => _undo.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'cards': cards.map((c) => c.toJson()).toList(),
        'connections': links.map((l) => l.toJson()).toList(),
        'shapes': shapes.map((s) => s.toJson()).toList(),
      };

  /// Bounding box of everything on the board (with margin), for fit-to-view and canvas size.
  Rect get bounds {
    Rect? r;
    for (final c in cards) {
      final cr = Rect.fromLTWH(c.x, c.y, cardSize.width, cardSize.height);
      r = r == null ? cr : r.expandToInclude(cr);
    }
    for (final s in shapes) {
      r = r == null ? s.rect : r.expandToInclude(s.rect);
    }
    final b = (r ?? const Rect.fromLTWH(0, 0, 800, 500)).inflate(40);
    return Rect.fromLTRB(math.max(0, b.left), math.max(0, b.top), b.right, b.bottom); // canvas starts at (0,0)
  }

  Size get extent {
    final b = bounds;
    return Size(math.max(1600, b.right + 400), math.max(1200, b.bottom + 400));
  }

  /// Call before any change the user should be able to undo.
  void checkpoint() {
    _undo.add(jsonEncode(toJson()));
    if (_undo.length > 60) _undo.removeAt(0);
  }

  void changed({bool mark = true}) {
    if (mark) edited = true;
    notifyListeners();
  }

  void replace(BoardData d) {
    cards = d.cards;
    links = d.links;
    shapes = d.shapes;
    selected = null;
    arrowFrom = null;
    tool = Tool.select;
    _undo.clear();
    edited = false;
    fitTick++;
    notifyListeners();
  }

  void clear() => replace(BoardData([], [], []));

  void undo() {
    if (_undo.isEmpty) return;
    final r = parseBoardJson(_undo.removeLast());
    if (r == null) return;
    cards = r.board.cards;
    links = r.board.links;
    shapes = r.board.shapes;
    selected = null;
    arrowFrom = null;
    changed();
  }

  void setTool(Tool t) {
    tool = tool == t ? Tool.select : t;
    arrowFrom = null;
    selected = null;
    notifyListeners();
  }

  void select(Object? o) {
    selected = o;
    notifyListeners();
  }

  CardModel addCard(Offset at, {String type = 'idea', String text = 'Type your idea here', String color = 'sand'}) {
    checkpoint();
    final c = CardModel('idea-${DateTime.now().microsecondsSinceEpoch}', type, text, math.max(0, at.dx), math.max(0, at.dy), color);
    cards.add(c);
    selected = c;
    changed();
    return c;
  }

  void deleteSelected() {
    final s = selected;
    if (s == null) return;
    checkpoint();
    if (s is CardModel) {
      cards.remove(s);
      links.removeWhere((l) => l.from == s.id || l.to == s.id);
    } else if (s is ShapeModel) {
      shapes.remove(s);
    } else if (s is Link) {
      links.remove(s);
    }
    selected = null;
    changed();
  }

  void connect(CardModel a, CardModel b) {
    if (a.id == b.id) return;
    checkpoint();
    final l = Link(a.id, b.id);
    links.add(l);
    selected = l;
    arrowFrom = null;
    tool = Tool.select;
    changed();
  }
}
