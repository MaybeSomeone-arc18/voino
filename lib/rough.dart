import 'dart:math' as math;
import 'dart:ui';

// Hand-drawn (Excalidraw-like) stroke helpers. A seeded Random keeps the wobble stable
// while an element moves or the board repaints.

Offset _jit(math.Random r, double m) => Offset((r.nextDouble() - .5) * 2 * m, (r.nextDouble() - .5) * 2 * m);

Path roughLine(Offset a, Offset b, math.Random r, {double wobble = 1.5}) {
  final d = b - a;
  if (d.distance < 1) return Path();
  final p = Path()..moveTo(a.dx + _jit(r, wobble * .6).dx, a.dy + _jit(r, wobble * .6).dy);
  final c1 = a + d * .3 + _jit(r, wobble), c2 = a + d * .7 + _jit(r, wobble), e = b + _jit(r, wobble * .6);
  p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
  return p;
}

Path roughRect(Rect rc, math.Random r, {double wobble = 1.5}) {
  final p = Path();
  double o() => r.nextDouble() * 5; // corners overshoot slightly, like a pen stroke
  final tl = rc.topLeft, tr = rc.topRight, br = rc.bottomRight, bl = rc.bottomLeft;
  p.addPath(roughLine(tl - Offset(o(), 0), tr + Offset(o(), 0), r, wobble: wobble), Offset.zero);
  p.addPath(roughLine(tr - Offset(0, o()), br + Offset(0, o()), r, wobble: wobble), Offset.zero);
  p.addPath(roughLine(br + Offset(o(), 0), bl - Offset(o(), 0), r, wobble: wobble), Offset.zero);
  p.addPath(roughLine(bl + Offset(0, o()), tl - Offset(0, o()), r, wobble: wobble), Offset.zero);
  return p;
}

Path roughEllipse(Rect rc, math.Random r, {double wobble = 1.5}) {
  const n = 36;
  final cx = rc.center.dx, cy = rc.center.dy, a = rc.width / 2, b = rc.height / 2;
  final start = r.nextDouble() * math.pi * 2, sweep = math.pi * 2 * 1.07; // overlap the ends
  final pts = <Offset>[
    for (var i = 0; i <= n; i++)
      Offset(cx + a * math.cos(start + sweep * i / n), cy + b * math.sin(start + sweep * i / n)) + _jit(r, wobble),
  ];
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = (pts[i] + pts[i + 1]) / 2;
    p.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  p.lineTo(pts.last.dx, pts.last.dy);
  return p;
}

/// Splits [src] into dashes, e.g. [8, 3, 2, 3] for the dash-dot look of the shape strokes.
Path dashPath(Path src, List<double> pattern) {
  final out = Path();
  for (final m in src.computeMetrics()) {
    var d = 0.0, i = 0;
    while (d < m.length) {
      final len = pattern[i % pattern.length];
      if (i.isEven) out.addPath(m.extractPath(d, math.min(d + len, m.length)), Offset.zero);
      d += len;
      i++;
    }
  }
  return out;
}

/// Draws [build] twice with different jitter for a double-stroked sketch look.
void sketch(Canvas c, Paint paint, int seed, Path Function(math.Random r) build, {List<double>? dash}) {
  for (var pass = 0; pass < 2; pass++) {
    final path = build(math.Random(seed * 31 + pass * 977));
    c.drawPath(dash == null ? path : dashPath(path, dash), paint);
  }
}

double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a, l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}
