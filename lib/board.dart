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
const _colW = 300.0, _rowH = 165.0, _top = 220.0, _maxCoord = 4000.0;

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

/// Turns notes into a mind-map: title card on top, one boxed column per topic,
/// a "To do" column, arrows for relationships and a circle on the key point.
BoardData buildBoard(Note n) {
  final cards = <CardModel>[], links = <Link>[], shapes = <ShapeModel>[];
  final columns = <(String, List<CardModel>)>[];
  final pointCard = <int, CardModel>{};

  var col = 0;
  for (final t in n.topics) {
    final list = <CardModel>[];
    for (var r = 0; r < t.points.length; r++) {
      final i = t.points[r];
      final c = CardModel('p$i', 'point', n.points[i], 24.0 + col * _colW, _top + r * _rowH);
      pointCard[i] = c;
      list.add(c);
    }
    columns.add((t.name, list));
    col++;
  }
  if (n.actions.isNotEmpty) {
    final list = [
      for (var r = 0; r < n.actions.length; r++)
        CardModel('a$r', 'action', n.actions[r], 24.0 + col * _colW, _top + r * _rowH, 'rose')
    ];
    columns.add(('To do', list));
    col++;
  }
  final title = CardModel('title', 'title', n.summary.isNotEmpty ? '${n.title}\n\n${n.summary}' : n.title,
      math.max(24.0, col * _colW / 2 - cardSize.width / 2 + 12), 24, 'sand');
  cards.add(title);

  for (final (name, list) in columns) {
    cards.addAll(list);
    final bottom = _top + (list.length - 1) * _rowH + cardSize.height;
    shapes.add(ShapeModel('box', Rect.fromLTRB(list.first.x - 12, _top - 40, list.first.x + cardSize.width + 12, bottom + 16), name));
    links.add(Link('title', list.first.id, name == 'To do' ? 'to do' : ''));
  }
  for (final l in n.links) {
    if (pointCard.containsKey(l.from) && pointCard.containsKey(l.to)) {
      links.add(Link('p${l.from}', 'p${l.to}', l.label));
    }
  }
  final k = n.keyPoint;
  if (k != null && pointCard.containsKey(k)) {
    final c = pointCard[k]!;
    shapes.add(ShapeModel('circle', Rect.fromLTWH(c.x, c.y, cardSize.width, cardSize.height).inflate(18), 'key'));
  }
  return BoardData(cards, links, shapes);
}

/// Parses a shared board JSON, clamping everything the same way the app expects.
({String title, String transcript, BoardData board})? parseBoardJson(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map || j['cards'] is! List) return null;
    double num0(dynamic v, double d, [double lo = 0, double hi = _maxCoord]) =>
        v is num && v.isFinite ? v.toDouble().clamp(lo, hi) : d;
    final cards = <CardModel>[];
    for (final c in (j['cards'] as List).take(60)) {
      if (c is! Map || c['text'] is! String || !['title', 'point', 'action', 'idea'].contains(c['type'])) continue;
      final color = cardColors.containsKey(c['color']) ? c['color'] as String : 'mint';
      cards.add(CardModel('${c['id'] ?? 'card-${cards.length}'}', c['type'] as String,
          (c['text'] as String).substring(0, math.min(1400, (c['text'] as String).length)),
          num0(c['x'], 24), num0(c['y'], 24), color));
    }
    final ids = cards.map((c) => c.id).toSet();
    final links = <Link>[];
    for (final l in ((j['connections'] ?? j['links']) as List? ?? []).take(60)) {
      if (l is Map && ids.contains('${l['from']}') && ids.contains('${l['to']}') && l['from'] != l['to']) {
        links.add(Link('${l['from']}', '${l['to']}', '${l['label'] ?? ''}'));
      }
    }
    final shapes = <ShapeModel>[];
    for (final s in ((j['shapes'] as List?) ?? []).take(40)) {
      if (s is! Map || !['circle', 'box'].contains(s['type']) || s['x'] is! num || s['y'] is! num) continue;
      shapes.add(ShapeModel(s['type'] as String,
          Rect.fromLTWH(num0(s['x'], 0), num0(s['y'], 0), num0(s['w'], 80, 8, 800), num0(s['h'], 80, 8, 800)),
          '${s['label'] ?? ''}'));
    }
    return (title: '${j['title'] ?? ''}', transcript: '${j['transcript'] ?? ''}', board: BoardData(cards, links, shapes));
  } catch (_) {
    return null;
  }
}

void _label(Canvas c, String text, Offset at, {double maxW = 240, Color color = const Color(0xFF6B4A38)}) {
  if (text.isEmpty) return;
  final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…')
    ..layout(maxWidth: maxW);
  tp.paint(c, at);
}

class BoardPainter extends CustomPainter {
  BoardPainter(this.cards, this.links, this.shapes);
  final List<CardModel> cards;
  final List<Link> links;
  final List<ShapeModel> shapes;

  @override
  void paint(Canvas c, Size s) {
    final sp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFAE7353);
    for (final sh in shapes) {
      if (sh.type == 'circle') {
        c.drawOval(sh.rect, sp);
        _label(c, sh.label, sh.rect.topCenter + const Offset(-10, -18));
      } else {
        c.drawRRect(RRect.fromRectAndRadius(sh.rect, const Radius.circular(7)), sp);
        _label(c, sh.label, sh.rect.topLeft + const Offset(10, 8));
      }
    }
    final lp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFF3F4A5A);
    final byId = {for (final x in cards) x.id: x};
    Rect r(CardModel m) => Rect.fromLTWH(m.x, m.y, cardSize.width, cardSize.height);
    // Point on the card edge in the direction of [to], so arrows stop at the card border.
    Offset edge(Rect box, Offset to) {
      final d = to - box.center;
      if (d == Offset.zero) return box.center;
      final t = math.min(d.dx == 0 ? double.infinity : (box.width / 2) / d.dx.abs(),
          d.dy == 0 ? double.infinity : (box.height / 2) / d.dy.abs());
      return box.center + d * t;
    }

    for (final l in links) {
      final a = byId[l.from], b = byId[l.to];
      if (a == null || b == null) continue;
      final p = edge(r(a), r(b).center), q = edge(r(b), r(a).center);
      c.drawLine(p, q, lp);
      final d = q - p;
      if (d.distance < 1) continue;
      final u = d / d.distance, nrm = Offset(-u.dy, u.dx);
      final base = q - u * 14;
      c.drawPath(
          Path()
            ..moveTo(q.dx, q.dy)
            ..lineTo((base + nrm * 7).dx, (base + nrm * 7).dy)
            ..lineTo((base - nrm * 7).dx, (base - nrm * 7).dy)
            ..close(),
          Paint()..color = lp.color);
      _label(c, l.label, Offset.lerp(p, q, 0.5)! + const Offset(6, -16), maxW: 140, color: const Color(0xFF3F4A5A));
    }
  }

  @override
  bool shouldRepaint(_) => true;
}
