import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'logic.dart';

const cardColors = {
  'mint': Color(0xFFD9EEDF),
  'sand': Color(0xFFF1E5C8),
  'lavender': Color(0xFFE2DCF3),
  'rose': Color(0xFFF6D9DA),
};
const cardSize = Size(260, 140);
const _colW = 290.0, _rowH = 170.0, _top = 40.0, _maxCoord = 4000.0;
const _pad = 28.0, _labelH = 44.0, _groupGap = 70.0, _sideGap = 130.0, _margin = 24.0;

class CardModel {
  CardModel(this.id, this.type, this.text, this.x, this.y, [this.color = 'mint']);
  String id, type, text, color; // type: title | point | action | idea
  double x, y;
  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'text': text, 'x': x, 'y': y, 'color': color};
}

class Link {
  Link(this.from, this.to, [this.label = '']);
  String from, to, label;
  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'label': label};
}

class ShapeModel {
  ShapeModel(this.type, this.rect, [this.label = '']);
  String type, label; // type: circle | box
  Rect rect;
  Map<String, dynamic> toJson() =>
      {'type': type, 'x': rect.left, 'y': rect.top, 'w': rect.width, 'h': rect.height, 'label': label};
}

class BoardData {
  BoardData(this.cards, this.links, this.shapes);
  final List<CardModel> cards;
  final List<Link> links;
  final List<ShapeModel> shapes;
}

final _decision = RegExp(r'\b(?:decided|decision|agreed|we will|we.ll go with|chose|concluded|approved)\b', caseSensitive: false);

/// Turns notes into a mind-map: the title card sits in the centre, topic groups (a box around
/// their cards) fan out to its left and right, and "To do" cards are rose. Groups are stacked per
/// side with fixed gaps, so cards never overlap. Arrows follow the links array; circles mark the
/// key point and decisions.
BoardData buildBoard(Note n) {
  final cards = <CardModel>[], links = <Link>[], shapes = <ShapeModel>[];
  final pointCard = <int, CardModel>{};

  // 1. Describe each group (name + cards); positions are computed below.
  final groups = <_Group>[];
  for (final t in n.topics) {
    if (t.points.isEmpty) continue;
    groups.add(_Group(t.name, [for (final i in t.points) (id: 'p$i', type: 'point', text: n.points[i], color: 'mint', point: i)]));
  }
  if (n.actions.isNotEmpty) {
    groups.add(_Group('To do', [
      for (var r = 0; r < n.actions.length; r++) (id: 'a$r', type: 'action', text: n.actions[r], color: 'rose', point: -1)
    ]));
  }

  // 2. Alternate sides, always giving the next group to the shorter side.
  final left = <_Group>[], right = <_Group>[];
  var lh = 0.0, rh = 0.0;
  for (final g in groups) {
    if (rh <= lh) {
      right.add(g);
      rh += g.height + _groupGap;
    } else {
      left.add(g);
      lh += g.height + _groupGap;
    }
  }
  final total = math.max(math.max(lh, rh) - _groupGap, cardSize.height);
  final leftW = left.isEmpty ? 0.0 : left.map((g) => g.width).reduce(math.max);
  final titleX = _margin + (left.isEmpty ? 0.0 : leftW + _sideGap);
  final titleY = _top + (total - cardSize.height) / 2;
  final rightX = titleX + cardSize.width + _sideGap;

  cards.add(CardModel('title', 'title', n.summary.isNotEmpty ? '${n.title}\n\n${n.summary}' : n.title, titleX, titleY, 'sand'));

  void place(List<_Group> side, double Function(_Group) xOf, double sideH) {
    if (side.isEmpty) return;
    var y = _top + (total - (sideH - _groupGap)) / 2;
    for (final g in side) {
      final x = xOf(g);
      CardModel? first;
      for (var k = 0; k < g.cards.length; k++) {
        final d = g.cards[k];
        final c = CardModel(d.id, d.type, d.text, x + _pad + (k % g.cols) * _colW, y + _labelH + (k ~/ g.cols) * _rowH, d.color);
        first ??= c;
        cards.add(c);
        if (d.point >= 0) pointCard[d.point] = c;
      }
      shapes.add(ShapeModel('box', Rect.fromLTWH(x, y, g.width, g.height), g.name));
      links.add(Link('title', first!.id, g.name == 'To do' ? 'to do' : ''));
      y += g.height + _groupGap;
    }
  }

  place(right, (_) => rightX, rh);
  place(left, (g) => _margin + leftW - g.width, lh); // right-aligned so groups hug the title

  for (final l in n.links) {
    if (pointCard.containsKey(l.from) && pointCard.containsKey(l.to)) {
      links.add(Link('p${l.from}', 'p${l.to}', l.label));
    }
  }
  // Circle the key point and up to two decisions ("we decided...", "agreed to...").
  final circled = <int, String>{};
  final k = n.keyPoint;
  if (k != null) circled[k] = 'key';
  for (var i = 0; i < n.points.length && circled.length < 3; i++) {
    if (!circled.containsKey(i) && _decision.hasMatch(n.points[i])) circled[i] = 'decision';
  }
  for (final e in circled.entries) {
    final c = pointCard[e.key];
    if (c != null) shapes.add(ShapeModel('circle', Rect.fromLTWH(c.x, c.y, cardSize.width, cardSize.height).inflate(14), e.value));
  }
  return BoardData(cards, links, shapes);
}

typedef _Item = ({String id, String type, String text, String color, int point});

class _Group {
  _Group(this.name, this.cards);
  final String name;
  final List<_Item> cards;
  int get cols => cards.length > 4 ? 2 : 1;
  int get rows => (cards.length / cols).ceil();
  double get width => _pad * 2 + cardSize.width + (cols - 1) * _colW;
  double get height => _labelH + cardSize.height + (rows - 1) * _rowH + _pad;
}

double _num(dynamic v, double d, [double lo = 0, double hi = _maxCoord]) =>
    v is num && v.isFinite ? v.toDouble().clamp(lo, hi) : d;

String _cut(dynamic v, int max) {
  final s = '${v ?? ''}';
  return s.substring(0, math.min(max, s.length));
}

/// Validates the `cards` of a board file: known types only, text and coordinates clamped,
/// duplicate ids dropped, at most 60 cards. Never throws.
List<CardModel> safeCards(dynamic raw) {
  final cards = <CardModel>[], seen = <String>{};
  if (raw is! List) return cards;
  for (final c in raw.take(60)) {
    if (c is! Map || c['text'] is! String || !['title', 'point', 'action', 'idea'].contains(c['type'])) continue;
    final id = '${c['id'] ?? 'card-${cards.length}'}';
    if (!seen.add(id)) continue;
    cards.add(CardModel(id, c['type'] as String, _cut(c['text'], 1400), _num(c['x'], 24), _num(c['y'], 24),
        cardColors.containsKey(c['color']) ? c['color'] as String : 'mint'));
  }
  return cards;
}

/// Validates arrows: both ends must be [ids] of real cards, no self-loops, at most 60.
List<Link> safeConnections(dynamic raw, Set<String> ids) {
  final links = <Link>[];
  if (raw is! List) return links;
  for (final l in raw.take(60)) {
    if (l is Map && ids.contains('${l['from']}') && ids.contains('${l['to']}') && '${l['from']}' != '${l['to']}') {
      links.add(Link('${l['from']}', '${l['to']}', _cut(l['label'], 60)));
    }
  }
  return links;
}

/// Validates circles and boxes: known types, numeric position, size clamped to 8..800, at most 40.
List<ShapeModel> safeShapes(dynamic raw) {
  final shapes = <ShapeModel>[];
  if (raw is! List) return shapes;
  for (final s in raw.take(40)) {
    if (s is! Map || !['circle', 'box'].contains(s['type']) || s['x'] is! num || s['y'] is! num) continue;
    shapes.add(ShapeModel(s['type'] as String,
        Rect.fromLTWH(_num(s['x'], 0), _num(s['y'], 0), _num(s['w'], 80, 8, 800), _num(s['h'], 80, 8, 800)), _cut(s['label'], 80)));
  }
  return shapes;
}

/// Parses a shared board JSON (as written by "Download board JSON"). Null if it is not a board.
({String title, String transcript, BoardData board})? parseBoardJson(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map || j['cards'] is! List) return null;
    final cards = safeCards(j['cards']);
    final links = safeConnections(j['connections'] ?? j['links'], cards.map((c) => c.id).toSet());
    return (title: '${j['title'] ?? ''}', transcript: '${j['transcript'] ?? ''}', board: BoardData(cards, links, safeShapes(j['shapes'])));
  } catch (_) {
    return null;
  }
}
