import 'dart:math' as math;
import 'dart:ui' show PointMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'board.dart';
import 'board_controller.dart';
import 'rough.dart';

const _ink = Color(0xFF2B2A28), _gold = Color(0xFFC4903F), _brown = Color(0xFFAE7353), _arrow = Color(0xFF3F4A5A);
const _paper = Color(0xFFFBF8F0);
const hand = 'Caveat';
const _colorOrder = ['mint', 'sand', 'lavender', 'rose'];
const _typeLabel = {'title': 'TITLE', 'point': 'POINT', 'action': 'TO DO', 'idea': 'MY IDEA'};

TextPainter _text(String s, double size, Color color, {double maxW = 300, FontWeight w = FontWeight.w600, int lines = 1}) =>
    TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: hand, fontSize: size, color: color, fontWeight: w, height: 1)),
      textDirection: TextDirection.ltr,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: maxW);

/// Excalidraw-style board: hand-drawn strokes, pan and zoom, selectable/movable/resizable elements.
class BoardPanel extends StatefulWidget {
  const BoardPanel({super.key, required this.controller, required this.onSave, required this.onOpen});
  final BoardController controller;
  final VoidCallback onSave, onOpen;

  @override
  State<BoardPanel> createState() => _BoardPanelState();
}

class _BoardPanelState extends State<BoardPanel> {
  final _tc = TransformationController();
  final _focus = FocusNode();
  Size _viewport = Size.zero;
  int _seenFit = -1;
  ShapeModel? _live;
  Offset? _dragStart;

  BoardController get c => widget.controller;
  double get _scale => _tc.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _tc.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _fit() {
    if (_viewport.isEmpty) return;
    final b = c.bounds;
    final s = math.min(_viewport.width / b.width, _viewport.height / b.height).clamp(0.25, 1.0);
    // Anchor to the canvas origin: centering would show empty space outside the canvas, where nothing can be drawn.
    _tc.value = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(-b.left * s, -b.top * s, 0);
  }

  String _hint() => switch (c.tool) {
        Tool.select => 'Drag cards and shapes to move them. Double-tap to edit. Drag empty space to pan, pinch or scroll to zoom.',
        Tool.box => 'Drag on empty space to draw a box.',
        Tool.circle => 'Drag on empty space to draw a circle.',
        Tool.arrow => c.arrowFrom == null ? 'Tap the first card.' : 'Now tap the card the arrow should point to.',
      };

  Widget _pill(String label, VoidCallback? f, {bool on = false}) => OutlinedButton(
        onPressed: f,
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          backgroundColor: on ? _gold.withValues(alpha: .28) : Colors.white,
          side: const BorderSide(color: _ink, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: hand, fontSize: 19, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        ),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final drawTool = c.tool == Tool.box || c.tool == Tool.circle;
    final height = math.max(420.0, math.min(720.0, MediaQuery.of(context).size.height * .62));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Make the notes your own.', style: TextStyle(fontFamily: hand, fontSize: 40, height: 1.05, color: _ink, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(_hint(), style: const TextStyle(fontFamily: hand, fontSize: 20, color: Colors.black54, height: 1.1)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _pill('+ Add a note', () {
          final at = _viewport.isEmpty ? const Offset(60, 60) : _tc.toScene(_viewport.center(Offset.zero));
          c.addCard(at - Offset(cardSize.width / 2, cardSize.height / 2));
        }),
        _pill(c.tool == Tool.arrow ? (c.arrowFrom == null ? 'Tap first card' : 'Tap second card') : 'Connect two cards',
            () => c.setTool(Tool.arrow), on: c.tool == Tool.arrow),
        _pill('Draw circle', () => c.setTool(Tool.circle), on: c.tool == Tool.circle),
        _pill('Draw box', () => c.setTool(Tool.box), on: c.tool == Tool.box),
        _pill('Edit text', c.selected == null ? null : _editSelected),
        _pill('Delete selected', c.selected == null ? null : c.deleteSelected),
        _pill('Undo', c.canUndo ? c.undo : null),
        _pill('Fit view', _fit),
        _pill('Save board .json', widget.onSave),
        _pill('Open board file', widget.onOpen),
      ]),
      const SizedBox(height: 12),
      Container(
        height: height,
        decoration: BoxDecoration(
          color: _paper,
          border: Border.all(color: _ink, width: 1.6),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: _ink.withValues(alpha: .16), offset: const Offset(4, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LayoutBuilder(builder: (ctx, cons) {
            _viewport = Size(cons.maxWidth, cons.maxHeight);
            if (_seenFit != c.fitTick) {
              _seenFit = c.fitTick;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fit();
              });
            }
            return _canvas(drawTool);
          }),
        ),
      ),
    ]);
  }

  Widget _canvas(bool drawTool) {
    final size = c.extent;
    final byId = {for (final k in c.cards) k.id: k};
    final sel = c.selected;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): c.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.backspace): c.deleteSelected,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
      },
      child: Focus(
        focusNode: _focus,
        child: Listener(
          onPointerDown: (_) => _focus.requestFocus(),
          child: InteractiveViewer(
            transformationController: _tc,
            constrained: false,
            minScale: .2,
            maxScale: 3,
            boundaryMargin: EdgeInsets.zero,
            panEnabled: !drawTool,
            scaleEnabled: !drawTool,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      c.arrowFrom = null;
                      c.select(null);
                    },
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: drawTool ? (e) => _dragStart = e.localPosition : null,
                      onPointerMove: drawTool
                          ? (e) {
                              if (_dragStart == null) return;
                              setState(() => _live = ShapeModel(c.tool == Tool.box ? 'box' : 'circle', Rect.fromPoints(_dragStart!, e.localPosition)));
                            }
                          : null,
                      onPointerUp: drawTool ? (_) => _finishDraw() : null,
                      onPointerCancel: drawTool ? (_) => setState(() => _live = null) : null,
                      child: const CustomPaint(painter: _GridPainter(), size: Size.infinite),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: drawTool,
                    child: Stack(clipBehavior: Clip.none, children: [
                      for (final s in c.shapes) _shape(s),
                      for (final l in c.links) ?_arrowView(l, byId),
                      for (final k in c.cards) _card(k),
                      if (sel is ShapeModel) _resizeHandle(sel),
                    ]),
                  ),
                ),
                if (_live != null) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _LivePainter(_live!)))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _finishDraw() {
    final s = _live;
    _dragStart = null;
    setState(() => _live = null);
    if (s != null && s.rect.width > 14 && s.rect.height > 14) {
      c.checkpoint();
      c.shapes.add(s);
      c.selected = s;
      c.tool = Tool.select;
      c.changed();
    }
  }

  // ---- elements -----------------------------------------------------------

  Widget _shape(ShapeModel s) {
    const pad = 18.0;
    return Positioned.fromRect(
      rect: s.rect.inflate(pad),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild, // only the stroke is grabbable, so cards inside stay clickable
        onTap: () => c.select(s),
        onDoubleTap: () => _editLabel(s),
        onPanStart: (_) {
          c.checkpoint();
          c.select(s);
        },
        onPanUpdate: (d) {
          s.rect = s.rect.shift(d.delta / _scale);
          c.changed();
        },
        child: CustomPaint(painter: _ShapePainter(s, identical(c.selected, s), pad)),
      ),
    );
  }

  Widget _resizeHandle(ShapeModel s) => Positioned(
        left: s.rect.right - 12,
        top: s.rect.bottom - 12,
        width: 24,
        height: 24,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => c.checkpoint(),
          onPanUpdate: (d) {
            final r = s.rect;
            s.rect = Rect.fromLTRB(r.left, r.top, math.max(r.left + 30, r.right + d.delta.dx / _scale),
                math.max(r.top + 30, r.bottom + d.delta.dy / _scale));
            c.changed();
          },
          child: Container(
            decoration: BoxDecoration(color: _gold, shape: BoxShape.circle, border: Border.all(color: _ink, width: 1.5)),
          ),
        ),
      );

  Offset _edge(Rect box, Offset to) {
    final d = to - box.center;
    if (d == Offset.zero) return box.center;
    final t = math.min(d.dx == 0 ? double.infinity : (box.width / 2) / d.dx.abs(), d.dy == 0 ? double.infinity : (box.height / 2) / d.dy.abs());
    return box.center + d * t;
  }

  Widget? _arrowView(Link l, Map<String, CardModel> byId) {
    final a = byId[l.from], b = byId[l.to];
    if (a == null || b == null) return null;
    final ra = Rect.fromLTWH(a.x, a.y, cardSize.width, cardSize.height), rb = Rect.fromLTWH(b.x, b.y, cardSize.width, cardSize.height);
    final p = _edge(ra, rb.center), q = _edge(rb, ra.center);
    final box = Rect.fromPoints(p, q).inflate(34);
    return Positioned.fromRect(
      rect: box,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => c.select(l),
        onDoubleTap: () => _editLabel(l),
        child: CustomPaint(painter: _ArrowPainter(p - box.topLeft, q - box.topLeft, l.label, identical(c.selected, l))),
      ),
    );
  }

  Widget _card(CardModel k) {
    final moving = c.tool == Tool.select;
    Widget iconBtn(IconData i, VoidCallback f, String tip) => Tooltip(
          message: tip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: f,
            child: Padding(padding: const EdgeInsets.all(5), child: Icon(i, size: 19, color: _ink)),
          ),
        );
    return Positioned(
      left: k.x,
      top: k.y,
      width: cardSize.width,
      height: cardSize.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tapCard(k),
        onDoubleTap: moving ? () => _editCard(k) : null,
        onPanStart: moving
            ? (_) {
                c.checkpoint();
                c.select(k);
              }
            : null,
        onPanUpdate: moving
            ? (d) {
                k.x = (k.x + d.delta.dx / _scale).clamp(0.0, 3700.0);
                k.y = (k.y + d.delta.dy / _scale).clamp(0.0, 3700.0);
                c.changed();
              }
            : null,
        child: CustomPaint(
          painter: _CardPainter(k, identical(c.selected, k), c.arrowFrom == k.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_typeLabel[k.type] ?? 'NOTE',
                    style: TextStyle(fontFamily: hand, fontSize: 16, letterSpacing: 1.4, fontWeight: FontWeight.w700, color: _ink.withValues(alpha: .6))),
                const Spacer(),
                iconBtn(Icons.contrast, () => _cycleColor(k), 'Change color'),
                iconBtn(Icons.close, () {
                  c.select(k);
                  c.deleteSelected();
                }, 'Delete'),
              ]),
              Expanded(
                child: Text(k.text,
                    maxLines: k.type == 'title' ? 5 : 4,
                    overflow: TextOverflow.fade,
                    style: TextStyle(fontFamily: hand, fontSize: k.type == 'title' ? 22 : 21, height: 1.05, color: _ink, fontWeight: k.type == 'title' ? FontWeight.w700 : FontWeight.w500)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- actions ------------------------------------------------------------

  void _tapCard(CardModel k) {
    if (c.tool != Tool.arrow) return c.select(k);
    final from = c.arrowFrom == null ? null : c.cards.where((x) => x.id == c.arrowFrom).firstOrNull;
    if (from == null) {
      c.arrowFrom = k.id;
      c.changed(mark: false);
    } else {
      c.connect(from, k);
    }
  }

  void _cycleColor(CardModel k) {
    c.checkpoint();
    k.color = _colorOrder[(_colorOrder.indexOf(k.color) + 1) % _colorOrder.length];
    c.changed();
  }

  void _editSelected() {
    final s = c.selected;
    if (s is CardModel) {
      _editCard(s);
    } else if (s != null) {
      _editLabel(s);
    }
  }

  Future<void> _editLabel(Object o) async {
    final current = o is ShapeModel ? o.label : (o as Link).label;
    final ctl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              title: Text(o is ShapeModel ? 'Label this shape' : 'Label this arrow'),
              content: TextField(controller: ctl, autofocus: true, maxLength: 60, decoration: const InputDecoration(hintText: 'e.g. leads to')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
              ],
            ));
    if (ok != true) return;
    c.checkpoint();
    if (o is ShapeModel) {
      o.label = ctl.text.trim();
    } else if (o is Link) {
      o.label = ctl.text.trim();
    }
    c.changed();
  }

  Future<void> _editCard(CardModel k) async {
    final ctl = TextEditingController(text: k.text);
    var color = k.color;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Edit card'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctl, maxLines: 5, maxLength: 1400, autofocus: true),
            Wrap(spacing: 8, children: [
              for (final e in cardColors.entries)
                GestureDetector(
                  onTap: () => setD(() => color = e.key),
                  child: CircleAvatar(radius: 15, backgroundColor: e.value, child: color == e.key ? const Icon(Icons.check, size: 15, color: _ink) : null),
                ),
            ]),
          ]),
          actions: [
            TextButton(
                onPressed: () {
                  Navigator.pop(d, false);
                  c.select(k);
                  c.deleteSelected();
                },
                child: const Text('Delete')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) {
      c.checkpoint();
      k.text = ctl.text;
      k.color = color;
      c.changed();
    }
  }
}

// ---- painters ---------------------------------------------------------------

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _ink.withValues(alpha: .14)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final pts = <Offset>[
      for (var x = 14.0; x < size.width; x += 28)
        for (var y = 14.0; y < size.height; y += 28) Offset(x, y),
    ];
    canvas.drawPoints(PointMode.points, pts, p);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _CardPainter extends CustomPainter {
  _CardPainter(this.k, this.selected, this.from);
  final CardModel k;
  final bool selected, from;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(3, 3, size.width - 10, size.height - 10), const Radius.circular(8));
    canvas.drawRRect(rr.shift(const Offset(4, 4)), Paint()..color = _ink.withValues(alpha: .16));
    canvas.drawRRect(rr, Paint()..color = cardColors[k.color] ?? cardColors['mint']!);
    final seed = k.id.hashCode;
    sketch(canvas, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round..color = _ink, seed,
        (r) => roughRect(rr.outerRect, r, wobble: 1.1));
    if (selected || from) {
      sketch(canvas, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.6..color = _gold, seed + 7,
          (r) => roughRect(rr.outerRect.inflate(7), r, wobble: .8), dash: const [9, 6]);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.s, this.selected, this.pad);
  final ShapeModel s;
  final bool selected;
  final double pad;

  Rect get _local => Rect.fromLTWH(pad, pad, s.rect.width, s.rect.height);

  @override
  bool? hitTest(Offset p) {
    final r = _local;
    if (s.type == 'circle') {
      final cx = r.center.dx, cy = r.center.dy, a = r.width / 2, b = r.height / 2;
      double v(double ra, double rb) => math.pow((p.dx - cx) / ra, 2).toDouble() + math.pow((p.dy - cy) / rb, 2).toDouble();
      return v(a + 12, b + 12) <= 1 && (a - 12 <= 0 || b - 12 <= 0 || v(a - 12, b - 12) >= 1);
    }
    final inner = r.deflate(12);
    return r.inflate(12).contains(p) && (inner.width <= 0 || inner.height <= 0 || !inner.contains(p));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = _local;
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round..color = _brown;
    sketch(canvas, stroke, s.hashCode, (rnd) => s.type == 'circle' ? roughEllipse(r, rnd) : roughRect(r, rnd), dash: const [8, 3, 2, 3]);
    if (s.label.isNotEmpty) {
      final tp = _text(s.label, 23, _brown, maxW: math.max(40, r.width - 20));
      tp.paint(canvas, s.type == 'circle' ? Offset(r.center.dx - tp.width / 2, r.top - tp.height - 2) : r.topLeft + const Offset(12, 8));
    }
    if (selected) {
      sketch(canvas, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = _gold, s.hashCode + 3,
          (rnd) => roughRect(r.inflate(7), rnd, wobble: .6), dash: const [7, 5]);
      for (final corner in [r.topLeft, r.topRight, r.bottomLeft]) {
        final h = Rect.fromCenter(center: corner + Offset(corner.dx == r.left ? -7 : 7, corner.dy == r.top ? -7 : 7), width: 9, height: 9);
        canvas.drawRect(h, Paint()..color = Colors.white);
        canvas.drawRect(h, Paint()..style = PaintingStyle.stroke..color = _ink..strokeWidth = 1.4);
      }
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.p, this.q, this.label, this.selected);
  final Offset p, q;
  final String label;
  final bool selected;

  @override
  bool? hitTest(Offset pos) => distanceToSegment(pos, p, q) <= 14;

  @override
  void paint(Canvas canvas, Size size) {
    final d = q - p;
    if (d.distance < 2) return;
    if (selected) canvas.drawLine(p, q, Paint()..color = _gold.withValues(alpha: .4)..strokeWidth = 10..strokeCap = StrokeCap.round);
    final seed = p.dx.round() * 7 + q.dy.round();
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.6..strokeCap = StrokeCap.round..color = _arrow;
    sketch(canvas, stroke, seed, (r) => roughLine(p, q, r, wobble: 2));
    final u = d / d.distance, n = Offset(-u.dy, u.dx);
    for (final side in [1, -1]) {
      final tip = q - u * 16 + n * (9.0 * side);
      sketch(canvas, stroke, seed + side, (r) => roughLine(q, tip, r, wobble: .8));
    }
    if (label.isNotEmpty) {
      final tp = _text(label, 21, _arrow, maxW: 150);
      final at = Offset.lerp(p, q, .5)! - Offset(tp.width / 2, tp.height / 2 + 12);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(at.dx - 5, at.dy - 2, tp.width + 10, tp.height + 4), const Radius.circular(6)),
          Paint()..color = _paper.withValues(alpha: .92));
      tp.paint(canvas, at);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.s);
  final ShapeModel s;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = _brown.withValues(alpha: .75);
    sketch(canvas, stroke, 5, (r) => s.type == 'circle' ? roughEllipse(s.rect, r) : roughRect(s.rect, r), dash: const [8, 3, 2, 3]);
  }

  @override
  bool shouldRepaint(_) => true;
}
