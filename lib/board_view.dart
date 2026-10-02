import 'dart:math' as math;
import 'dart:ui' show PointMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'board.dart';
import 'board_controller.dart';
import 'board_glass.dart';
import 'rough.dart';

const _ink = Color(0xFF2B2A28),
    _gold = Color(0xFFC4903F),
    _brown = Color(0xFFAE7353),
    _arrow = Color(0xFF3F4A5A);
const _paper = Color(0xFFFBF8F0);
const hand = 'Caveat';
const _colorOrder = ['mint', 'sand', 'lavender', 'rose'];
const _typeLabel = {
  'title': 'TITLE',
  'point': 'POINT',
  'action': 'TO DO',
  'idea': 'MY IDEA',
};

TextPainter _text(
  String s,
  double size,
  Color color, {
  double maxW = 300,
  FontWeight w = FontWeight.w600,
  int lines = 1,
}) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(
      fontFamily: hand,
      fontSize: size,
      color: color,
      fontWeight: w,
      height: 1,
    ),
  ),
  textDirection: TextDirection.ltr,
  maxLines: lines,
  ellipsis: '…',
)..layout(maxWidth: maxW);

/// Excalidraw-style board: hand-drawn strokes, pan and zoom, selectable/movable/resizable elements.
class BoardPanel extends StatefulWidget {
  const BoardPanel({
    super.key,
    required this.controller,
    required this.onSave,
    required this.onOpen,
  });
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
  bool _panMode = false;
  Object?
  _editing; // CardModel | ShapeModel | Link whose text is being typed in place
  bool _editIsNew = false;
  final _etc = TextEditingController();
  final _efocus = FocusNode();
  Offset _dblAt = Offset.zero;
  bool get _mobile => MediaQuery.sizeOf(context).width < 600;

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
    _etc.dispose();
    _efocus.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // Selecting something else, switching tool or undoing ends the edit and keeps the text.
    if (_editing != null && !identical(c.selected, _editing)) _commitEdit();
    setState(() {});
  }

  // Room above and below the content, so the floating bars never have to cover it.
  static const _padTop = 72.0, _padBottom = 96.0, _padSide = 12.0;

  void _fit() {
    if (_viewport.isEmpty) return;
    final b = c.bounds;
    final s = math
        .min(
          (_viewport.width - 2 * _padSide) / b.width,
          (_viewport.height - _padTop - _padBottom) / b.height,
        )
        .clamp(0.25, 1.0);
    _tc.value = Matrix4.diagonal3Values(s, s, 1)
      ..setTranslationRaw(_padSide - b.left * s, _padTop - b.top * s, 0);
  }

  String _hint() => switch (c.tool) {
    Tool.select =>
      _mobile
          ? 'Tap to select. Double-tap to write. Move pans; pinch to zoom.'
          : 'Drag cards to move them. Double-click to edit. Drag empty space to pan. Double-click anything to write in it. Keys: T text, V select, N note, R box, O circle, A arrow, ? for all.',
    Tool.box => 'Drag on empty space to draw a box.',
    Tool.circle => 'Drag on empty space to draw a circle.',
    Tool.text => 'Tap anywhere to write.',
    Tool.arrow =>
      c.arrowFrom == null
          ? 'Tap the first card.'
          : 'Now tap the card the arrow should point to.',
  };

  Widget build(BuildContext context) {
    final drawTool = c.tool == Tool.box || c.tool == Tool.circle;
    final height = math.max(
      460.0,
      math.min(720.0, MediaQuery.of(context).size.height * .66),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _mobile ? 'Your board' : 'Make the notes your own.',
          style: TextStyle(
            fontFamily: hand,
            fontSize: 40,
            height: 1.05,
            color: _ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _panMode ? 'Drag anywhere to move. Pinch to zoom.' : _hint(),
          style: TextStyle(
            fontFamily: hand,
            fontSize: 20,
            color: _ink.withValues(alpha: .68),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: _paper,
            border: Border.all(color: _ink.withValues(alpha: .2), width: 1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: LayoutBuilder(
              builder: (ctx, cons) {
                _viewport = Size(cons.maxWidth, cons.maxHeight);
                if (_seenFit != c.fitTick) {
                  _seenFit = c.fitTick;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _fit();
                  });
                }
                return Stack(
                  children: [
                    Positioned.fill(child: _canvas(drawTool)),
                    Positioned(top: 10, right: 10, child: _viewBar()),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (c.selected != null) ...[
                            _selectionBar(),
                            const SizedBox(height: 8),
                          ],
                          _mobile ? _mobileTools() : _toolBar(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Top-right cluster: undo, redo, zoom, and (on larger screens) fit and file actions.
  Widget _viewBar() => BoardBar(
    radius: 14,
    padding: const EdgeInsets.all(4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BoardButton(
          icon: Icons.undo,
          tooltip: 'Undo',
          onPressed: c.canUndo ? c.undo : null,
        ),
        BoardButton(
          icon: Icons.redo,
          tooltip: 'Redo',
          onPressed: c.canRedo ? c.redo : null,
        ),
        if (!_mobile) ...[
          BoardButton(
            icon: Icons.keyboard_outlined,
            tooltip: 'Shortcuts (?)',
            onPressed: _showShortcuts,
          ),
          BoardButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onPressed: () => _zoom(1 / 1.35),
          ),
          BoardButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            onPressed: () => _zoom(1.35),
          ),
          BoardButton(
            icon: Icons.fit_screen,
            tooltip: 'Fit view',
            onPressed: _fit,
          ),
          BoardButton(
            icon: Icons.download,
            tooltip: 'Save board .json',
            onPressed: widget.onSave,
          ),
          BoardButton(
            icon: Icons.folder_open,
            tooltip: 'Open board file',
            onPressed: widget.onOpen,
          ),
        ],
      ],
    ),
  );

  /// Appears only while something is selected, like Excalidraw's properties panel.
  Widget _selectionBar() {
    final sel = c.selected;
    return BoardBar(
      radius: 14,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoardButton(
            label: _mobile ? 'Edit' : 'Edit text',
            onPressed: _editSelected,
          ),
          if (sel is CardModel || sel is ShapeModel)
            BoardButton(
              icon: Icons.copy_all_outlined,
              tooltip: 'Duplicate',
              onPressed: c.duplicateSelected,
            ),
          BoardButton(
            label: _mobile ? 'Delete' : 'Delete selected',
            onPressed: c.deleteSelected,
          ),
        ],
      ),
    );
  }

  Widget _toolBar() => BoardBar(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoardButton(label: '+ Add a note', onPressed: _addNote),
          const SizedBox(width: 6),
          BoardButton(
            label: c.tool == Tool.arrow
                ? (c.arrowFrom == null ? 'Tap first card' : 'Tap second card')
                : 'Connect two cards',
            tooltip: 'Connect (A)',
            onPressed: () => c.setTool(Tool.arrow),
            on: c.tool == Tool.arrow,
          ),
          const SizedBox(width: 6),
          BoardButton(
            label: 'Draw circle',
            tooltip: 'Circle (O)',
            onPressed: () => c.setTool(Tool.circle),
            on: c.tool == Tool.circle,
          ),
          const SizedBox(width: 6),
          BoardButton(
            label: 'Draw box',
            tooltip: 'Box (R)',
            onPressed: () => c.setTool(Tool.box),
            on: c.tool == Tool.box,
          ),
          const SizedBox(width: 6),
          BoardButton(
            label: 'Text',
            tooltip: 'Text (T)',
            onPressed: () => c.setTool(Tool.text),
            on: c.tool == Tool.text,
          ),
          const SizedBox(width: 6),
          BoardButton(
            icon: Icons.more_horiz,
            tooltip: 'More board tools',
            onPressed: _moreTools,
          ),
        ],
      ),
    ),
  );

  void _addNote() {
    final at = _viewport.isEmpty
        ? const Offset(60, 60)
        : _tc.toScene(_viewport.center(Offset.zero));
    _panMode = false;
    c.setTool(Tool.select);
    c.addCard(at - Offset(cardSize.width / 2, cardSize.height / 2));
  }

  void _zoom(double factor) {
    if (_viewport.isEmpty) return;
    final oldScale = _scale;
    final next = (oldScale * factor).clamp(.2, 3.0);
    final center = _viewport.center(Offset.zero);
    final selected = c.selected;
    final scene = selected is CardModel
        ? Offset(
            selected.x + cardSize.width / 2,
            selected.y + cardSize.height / 2,
          )
        : selected is ShapeModel
        ? selected.rect.center
        : c.bounds.center;
    _tc.value = Matrix4.diagonal3Values(next, next, 1)
      ..setTranslationRaw(
        center.dx - scene.dx * next,
        center.dy - scene.dy * next,
        0,
      );
  }

  Widget _mobileTools() => BoardBar(
    padding: const EdgeInsets.all(5),
    child: Row(
      children: [
        Expanded(
          child: BoardButton(
            label: 'Select',
            onPressed: () {
              setState(() => _panMode = false);
              if (c.tool != Tool.select) c.setTool(Tool.select);
            },
            on: !_panMode && c.tool == Tool.select,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: BoardButton(
            label: 'Move',
            onPressed: () {
              if (c.tool != Tool.select) c.setTool(Tool.select);
              c.select(null);
              setState(() => _panMode = true);
            },
            on: _panMode,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: BoardButton(label: '+ Note', onPressed: _addNote),
        ),
        const SizedBox(width: 4),
        BoardButton(
          icon: Icons.more_horiz,
          tooltip: 'More board tools',
          onPressed: _moreTools,
        ),
      ],
    ),
  );

  void _moreTools() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _paper,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Material(
            color: _paper,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Text(
                      'Board tools',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                  for (final item in <(String, IconData, VoidCallback)>[
                    (
                      'Connect cards',
                      Icons.arrow_forward,
                      () => c.setTool(Tool.arrow),
                    ),
                    (
                      'Draw circle',
                      Icons.circle_outlined,
                      () => c.setTool(Tool.circle),
                    ),
                    ('Draw box', Icons.crop_square, () => c.setTool(Tool.box)),
                    ('Add text', Icons.text_fields, () => c.setTool(Tool.text)),
                    ('Fit view', Icons.fit_screen, _fit),
                    ('Zoom in', Icons.zoom_in, () => _zoom(1.35)),
                    ('Zoom out', Icons.zoom_out, () => _zoom(1 / 1.35)),
                    ('Save board .json', Icons.download, widget.onSave),
                    ('Open board file', Icons.folder_open, widget.onOpen),
                    (
                      'Keyboard shortcuts',
                      Icons.keyboard_outlined,
                      _showShortcuts,
                    ),
                  ])
                    ListTile(
                      leading: Icon(item.$2, color: _ink),
                      title: Text(
                        item.$1,
                        style: const TextStyle(color: _ink, fontSize: 16),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() => _panMode = false);
                        item.$3();
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _canvas(bool drawTool) {
    final size = c.extent;
    final byId = {for (final k in c.cards) k.id: k};
    final sel = c.selected;
    // While typing in place only Escape is bound, so letters and Backspace go to the text.
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): c.undo,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
          c.redo,
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): c.redo,
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
      const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
          c.duplicateSelected,
      const SingleActivator(LogicalKeyboardKey.keyD, control: true):
          c.duplicateSelected,
      const SingleActivator(LogicalKeyboardKey.delete): c.deleteSelected,
      const SingleActivator(LogicalKeyboardKey.backspace): c.deleteSelected,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        _panMode = false;
        c.arrowFrom = null;
        if (c.tool != Tool.select) c.setTool(Tool.select);
        c.select(null);
      },
      const SingleActivator(LogicalKeyboardKey.keyV): () {
        if (c.tool != Tool.select) c.setTool(Tool.select);
      },
      const SingleActivator(LogicalKeyboardKey.keyH): () =>
          setState(() => _panMode = !_panMode),
      const SingleActivator(LogicalKeyboardKey.keyN): _addNote,
      const SingleActivator(LogicalKeyboardKey.keyT): () {
        if (c.tool != Tool.text) c.setTool(Tool.text);
      },
      const SingleActivator(LogicalKeyboardKey.enter): _editSelected,
      const SingleActivator(LogicalKeyboardKey.slash, shift: true):
          _showShortcuts,
      const SingleActivator(LogicalKeyboardKey.keyR): () {
        if (c.tool != Tool.box) c.setTool(Tool.box);
      },
      const SingleActivator(LogicalKeyboardKey.keyO): () {
        if (c.tool != Tool.circle) c.setTool(Tool.circle);
      },
      const SingleActivator(LogicalKeyboardKey.keyA): () {
        if (c.tool != Tool.arrow) c.setTool(Tool.arrow);
      },
      const SingleActivator(LogicalKeyboardKey.digit1, shift: true): _fit,
      const SingleActivator(LogicalKeyboardKey.equal): () => _zoom(1.35),
      const SingleActivator(LogicalKeyboardKey.minus): () => _zoom(1 / 1.35),
    };
    final editBindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): () => c.select(null),
    };
    return CallbackShortcuts(
      bindings: _editing != null ? editBindings : bindings,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: (node, e) {
          // Typing with something selected starts writing in it (tool letters keep their job).
          final ch = e.character;
          if (e is KeyDownEvent &&
              _editing == null &&
              c.selected != null &&
              ch != null &&
              ch.length == 1 &&
              ch.trim().isNotEmpty &&
              !HardwareKeyboard.instance.isControlPressed &&
              !HardwareKeyboard.instance.isMetaPressed &&
              !HardwareKeyboard.instance.isAltPressed &&
              !'vhtnroa+-=?1!'.contains(ch.toLowerCase())) {
            _beginEdit(c.selected!, seed: ch);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Listener(
          onPointerDown: (_) {
            if (_editing == null) _focus.requestFocus();
          },
          child: InteractiveViewer(
            transformationController: _tc,
            constrained: false,
            minScale: .2,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.fromLTRB(
              _padSide,
              _padTop,
              _padSide,
              _padBottom,
            ),
            panEnabled: !drawTool,
            scaleEnabled: !drawTool,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        if (c.tool == Tool.text) {
                          final t = c.addText(d.localPosition);
                          _beginEdit(t);
                          return;
                        }
                        c.arrowFrom = null;
                        c.select(null);
                      },
                      onDoubleTapDown: (d) => _dblAt = d.localPosition,
                      onDoubleTap: _doubleTapCanvas,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: drawTool
                            ? (e) => _dragStart = e.localPosition
                            : null,
                        onPointerMove: drawTool
                            ? (e) {
                                if (_dragStart == null) return;
                                setState(
                                  () => _live = ShapeModel(
                                    c.tool == Tool.box ? 'box' : 'circle',
                                    Rect.fromPoints(
                                      _dragStart!,
                                      e.localPosition,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        onPointerUp: drawTool ? (_) => _finishDraw() : null,
                        onPointerCancel: drawTool
                            ? (_) => setState(() {
                                _live = null;
                                _dragStart = null;
                              })
                            : null,
                        child: const CustomPaint(
                          painter: _GridPainter(),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: drawTool || _panMode || c.tool == Tool.text,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final s in c.shapes) _shape(s),
                          for (final l in c.links) ?_arrowView(l, byId),
                          for (final k in c.cards) _card(k),
                          if (sel is ShapeModel &&
                              !_panMode &&
                              _editing == null)
                            _resizeHandle(sel),
                          if (_editing != null) _editor(_editing!, byId),
                        ],
                      ),
                    ),
                  ),
                  if (_live != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _LivePainter(_live!)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Double-click on empty canvas writes there; inside a shape it writes in the shape.
  void _doubleTapCanvas() {
    if (c.tool != Tool.select) return;
    final p = _dblAt;
    for (final s in c.shapes.reversed) {
      if (s.rect.contains(p)) {
        _beginEdit(s);
        return;
      }
    }
    final t = c.addText(p);
    _beginEdit(t);
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
        behavior: HitTestBehavior
            .deferToChild, // only the stroke is grabbable, so cards inside stay clickable
        onTap: () => c.select(s),
        onDoubleTap: () => _beginEdit(s),
        onPanStart: (_) {
          c.checkpoint();
          c.select(s);
        },
        onPanUpdate: (d) {
          s.rect = s.rect.shift(d.delta / _scale);
          c.changed();
        },
        child: CustomPaint(
          painter: _ShapePainter(s, identical(c.selected, s), pad),
        ),
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
        s.rect = Rect.fromLTRB(
          r.left,
          r.top,
          math.max(r.left + 30, r.right + d.delta.dx / _scale),
          math.max(r.top + 30, r.bottom + d.delta.dy / _scale),
        );
        c.changed();
      },
      child: Container(
        decoration: BoxDecoration(
          color: _gold,
          shape: BoxShape.circle,
          border: Border.all(color: _ink, width: 1.5),
        ),
      ),
    ),
  );

  Offset _edge(Rect box, Offset to) {
    final d = to - box.center;
    if (d == Offset.zero) return box.center;
    final t = math.min(
      d.dx == 0 ? double.infinity : (box.width / 2) / d.dx.abs(),
      d.dy == 0 ? double.infinity : (box.height / 2) / d.dy.abs(),
    );
    return box.center + d * t;
  }

  Widget? _arrowView(Link l, Map<String, CardModel> byId) {
    final a = byId[l.from], b = byId[l.to];
    if (a == null || b == null) return null;
    final ra = Rect.fromLTWH(a.x, a.y, cardSize.width, cardSize.height),
        rb = Rect.fromLTWH(b.x, b.y, cardSize.width, cardSize.height);
    final p = _edge(ra, rb.center), q = _edge(rb, ra.center);
    final box = Rect.fromPoints(p, q).inflate(34);
    return Positioned.fromRect(
      rect: box,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => c.select(l),
        onDoubleTap: () => _beginEdit(l),
        child: CustomPaint(
          painter: _ArrowPainter(
            p - box.topLeft,
            q - box.topLeft,
            l.label,
            identical(c.selected, l),
          ),
        ),
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
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(i, size: 19, color: _ink),
          ),
        ),
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
        onDoubleTap: moving ? () => _beginEdit(k) : null,
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
          painter: _CardPainter(
            k,
            identical(c.selected, k),
            c.arrowFrom == k.id,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _typeLabel[k.type] ?? 'NOTE',
                      style: TextStyle(
                        fontFamily: hand,
                        fontSize: 16,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                        color: _ink.withValues(alpha: .6),
                      ),
                    ),
                    const Spacer(),
                    if (!_mobile || identical(c.selected, k))
                      iconBtn(
                        Icons.contrast,
                        () => _cycleColor(k),
                        'Change color',
                      ),
                    if (!_mobile)
                      iconBtn(Icons.close, () {
                        c.select(k);
                        c.deleteSelected();
                      }, 'Delete'),
                  ],
                ),
                Expanded(
                  child: Text(
                    k.text,
                    maxLines: k.type == 'title' ? 5 : 4,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontFamily: hand,
                      fontSize: k.type == 'title' ? 22 : 21,
                      height: 1.05,
                      color: _ink,
                      fontWeight: k.type == 'title'
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- actions ------------------------------------------------------------

  void _tapCard(CardModel k) {
    if (c.tool != Tool.arrow) return c.select(k);
    final from = c.arrowFrom == null
        ? null
        : c.cards.where((x) => x.id == c.arrowFrom).firstOrNull;
    if (from == null) {
      c.arrowFrom = k.id;
      c.changed(mark: false);
    } else {
      c.connect(from, k);
    }
  }

  void _cycleColor(CardModel k) {
    c.checkpoint();
    k.color =
        _colorOrder[(_colorOrder.indexOf(k.color) + 1) % _colorOrder.length];
    c.changed();
  }

  void _editSelected() {
    final s = c.selected;
    if (s != null) _beginEdit(s);
  }

  String _textOf(Object o) => o is CardModel
      ? o.text
      : o is ShapeModel
      ? o.label
      : (o as Link).label;

  /// Writes in place, the way Excalidraw does: no dialog, the text field sits on the element.
  void _beginEdit(Object o, {String? seed}) {
    if (_editing != null && !identical(_editing, o)) _commitEdit();
    _panMode = false;
    _editing = o;
    _editIsNew = o is ShapeModel && o.type == 'text' && o.label.isEmpty;
    final t = seed ?? _textOf(o);
    _etc.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
    if (!identical(c.selected, o)) c.select(o);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing == o) _efocus.requestFocus();
    });
  }

  void _commitEdit() {
    final o = _editing;
    if (o == null) return;
    _editing = null;
    final v = _etc.text;
    final isNew = _editIsNew;
    _editIsNew = false;
    if (o is ShapeModel && o.type == 'text' && v.trim().isEmpty) {
      // An empty text element is not kept (and an empty new one leaves no undo step).
      if (isNew) {
        c.undo();
      } else {
        c.select(o);
        c.deleteSelected();
      }
      return;
    }
    if (v != _textOf(o)) {
      if (!isNew) c.checkpoint();
      if (o is CardModel) {
        o.text = v.length > 1400 ? v.substring(0, 1400) : v;
      } else if (o is ShapeModel) {
        o.label = v.length > 400 ? v.substring(0, 400) : v;
        if (o.type == 'text') {
          final tp = _text(o.label, 26, _ink, maxW: o.rect.width, lines: 12);
          o.rect = Rect.fromLTWH(
            o.rect.left,
            o.rect.top,
            o.rect.width,
            math.max(44, tp.height + 14),
          );
        }
      } else if (o is Link) {
        o.label = v.length > 60 ? v.substring(0, 60) : v;
      }
      c.changed();
    }
  }

  /// Where the in-place editor sits (scene coordinates) and which style it uses.
  Widget _editor(Object o, Map<String, CardModel> byId) {
    Rect r;
    TextStyle style;
    Color fill = Colors.white;
    var multi = true;
    if (o is CardModel) {
      r = Rect.fromLTWH(
        o.x + 8,
        o.y + 8,
        cardSize.width - 22,
        cardSize.height - 22,
      );
      fill = cardColors[o.color] ?? Colors.white;
      style = TextStyle(
        fontFamily: hand,
        fontSize: o.type == 'title' ? 22 : 21,
        height: 1.05,
        color: _ink,
        fontWeight: o.type == 'title' ? FontWeight.w700 : FontWeight.w500,
      );
    } else if (o is ShapeModel && o.type == 'text') {
      r = Rect.fromLTWH(
        o.rect.left,
        o.rect.top,
        math.max(160, o.rect.width),
        44,
      );
      style = const TextStyle(
        fontFamily: hand,
        fontSize: 26,
        height: 1.1,
        color: _ink,
        fontWeight: FontWeight.w600,
      );
    } else if (o is ShapeModel) {
      final w = math.max(120.0, math.min(240.0, o.rect.width - 16));
      r = o.type == 'circle'
          ? Rect.fromLTWH(o.rect.center.dx - w / 2, o.rect.top - 34, w, 34)
          : Rect.fromLTWH(o.rect.left + 8, o.rect.top + 6, w, 34);
      style = const TextStyle(
        fontFamily: hand,
        fontSize: 23,
        color: _brown,
        fontWeight: FontWeight.w600,
      );
      multi = false;
    } else {
      final l = o as Link;
      final a = byId[l.from], b = byId[l.to];
      final mid = a == null || b == null
          ? const Offset(60, 60)
          : (Offset(a.x, a.y) + Offset(b.x, b.y)) / 2 +
                Offset(cardSize.width / 2, cardSize.height / 2);
      r = Rect.fromCenter(center: mid, width: 150, height: 34);
      style = const TextStyle(
        fontFamily: hand,
        fontSize: 20,
        color: _arrow,
        fontWeight: FontWeight.w600,
      );
      multi = false;
    }
    return Positioned.fromRect(
      rect: r,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _gold, width: 1.6),
        ),
        child: Focus(
          onKeyEvent: (n, e) {
            if (e is KeyDownEvent &&
                e.logicalKey == LogicalKeyboardKey.escape) {
              c.select(null); // ends the edit and keeps what was typed
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: _etc,
            focusNode: _efocus,
            maxLines: multi ? null : 1,
            minLines: 1,
            style: style,
            cursorColor: _gold,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
            ),
            onSubmitted: multi ? null : (_) => c.select(null),
          ),
        ),
      ),
    );
  }

  void _showShortcuts() {
    const rows = [
      ('V', 'Select'),
      ('H', 'Hand: drag to move the canvas'),
      ('T', 'Text: tap anywhere and write'),
      ('N', 'New note card'),
      ('R', 'Draw a box'),
      ('O', 'Draw a circle'),
      ('A', 'Connect two cards with an arrow'),
      ('Double-click', 'Write in anything, or on empty space'),
      ('Enter', 'Write in the selected item'),
      ('Esc', 'Finish writing, or go back to select'),
      ('Ctrl/Cmd + D', 'Duplicate'),
      ('Ctrl/Cmd + Z', 'Undo (add Shift to redo)'),
      ('Delete', 'Delete selected'),
      ('Shift + 1', 'Fit view'),
      ('+ / -', 'Zoom'),
    ];
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: _paper,
        title: const Text('Board shortcuts'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            r.$1,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(child: Text(r.$2)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ---- painters ---------------------------------------------------------------

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _ink.withValues(alpha: .11)
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
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(3, 3, size.width - 10, size.height - 10),
      const Radius.circular(14),
    );
    final fill = cardColors[k.color] ?? cardColors['mint']!;
    // Soft shadow instead of a hard offset, a thin edge in a darker tint of the card colour.
    canvas.drawRRect(
      rr.shift(const Offset(0, 2)),
      Paint()
        ..color = _ink.withValues(alpha: .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(rr, Paint()..color = fill);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Color.lerp(fill, _ink, .38)!,
    );
    if (selected || from) {
      canvas.drawRRect(
        rr.inflate(5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..color = _gold,
      );
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
    if (s.type == 'text') return r.inflate(8).contains(p);
    if (s.type == 'circle') {
      final cx = r.center.dx,
          cy = r.center.dy,
          a = r.width / 2,
          b = r.height / 2;
      double v(double ra, double rb) =>
          math.pow((p.dx - cx) / ra, 2).toDouble() +
          math.pow((p.dy - cy) / rb, 2).toDouble();
      return v(a + 12, b + 12) <= 1 &&
          (a - 12 <= 0 || b - 12 <= 0 || v(a - 12, b - 12) >= 1);
    }
    final inner = r.deflate(12);
    return r.inflate(12).contains(p) &&
        (inner.width <= 0 || inner.height <= 0 || !inner.contains(p));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = _local;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = _brown;
    if (s.type == 'text') {
      if (s.label.isNotEmpty) {
        _text(
          s.label,
          26,
          _ink,
          maxW: r.width,
          lines: 12,
        ).paint(canvas, r.topLeft + const Offset(0, 6));
      }
    } else {
      sketch(
        canvas,
        stroke,
        s.hashCode,
        (rnd) => s.type == 'circle' ? roughEllipse(r, rnd) : roughRect(r, rnd),
        dash: const [8, 3, 2, 3],
      );
    }
    if (s.type != 'text' && s.label.isNotEmpty) {
      final tp = _text(s.label, 23, _brown, maxW: math.max(40, r.width - 20));
      tp.paint(
        canvas,
        s.type == 'circle'
            ? Offset(r.center.dx - tp.width / 2, r.top - tp.height - 2)
            : r.topLeft + const Offset(12, 8),
      );
    }
    if (selected) {
      sketch(
        canvas,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _gold,
        s.hashCode + 3,
        (rnd) => roughRect(r.inflate(7), rnd, wobble: .6),
        dash: const [7, 5],
      );
      for (final corner in [r.topLeft, r.topRight, r.bottomLeft]) {
        final h = Rect.fromCenter(
          center:
              corner +
              Offset(corner.dx == r.left ? -7 : 7, corner.dy == r.top ? -7 : 7),
          width: 9,
          height: 9,
        );
        canvas.drawRect(h, Paint()..color = _paper);
        canvas.drawRect(
          h,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = _ink
            ..strokeWidth = 1.4,
        );
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
    if (selected)
      canvas.drawLine(
        p,
        q,
        Paint()
          ..color = _gold.withValues(alpha: .4)
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    final seed = p.dx.round() * 7 + q.dy.round();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = _arrow;
    sketch(canvas, stroke, seed, (r) => roughLine(p, q, r, wobble: 2));
    final u = d / d.distance, n = Offset(-u.dy, u.dx);
    for (final side in [1, -1]) {
      final tip = q - u * 16 + n * (9.0 * side);
      sketch(
        canvas,
        stroke,
        seed + side,
        (r) => roughLine(q, tip, r, wobble: .8),
      );
    }
    if (label.isNotEmpty) {
      final tp = _text(label, 21, _arrow, maxW: 150);
      final at =
          Offset.lerp(p, q, .5)! - Offset(tp.width / 2, tp.height / 2 + 12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(at.dx - 5, at.dy - 2, tp.width + 10, tp.height + 4),
          const Radius.circular(6),
        ),
        Paint()..color = _paper.withValues(alpha: .92),
      );
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
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _brown.withValues(alpha: .75);
    sketch(
      canvas,
      stroke,
      5,
      (r) =>
          s.type == 'circle' ? roughEllipse(s.rect, r) : roughRect(s.rect, r),
      dash: const [8, 3, 2, 3],
    );
  }

  @override
  bool shouldRepaint(_) => true;
}
