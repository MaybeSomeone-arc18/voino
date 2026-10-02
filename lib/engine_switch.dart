import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'feedback_stub.dart' if (dart.library.js_interop) 'feedback_web.dart';

/// Minimal two-way switch between cloud speech ('device') and on-device Whisper ('whisper').
/// A pill slides between the two sides with a small overshoot, icons scale up on the active
/// side and the hint line cross-fades.
class EngineSwitch extends StatefulWidget {
  const EngineSwitch({
    super.key,
    required this.engine,
    required this.onChanged,
    required this.ink,
    required this.paper,
    this.cloudEnabled = true,
    this.enabled = true,
    this.accent = const Color(0xFFC4903F),
  });

  final String engine; // 'device' (cloud) | 'whisper' (on-device) | 'gemini' (cloud, free tier)
  final ValueChanged<String> onChanged;
  final Color ink, paper, accent;
  final bool cloudEnabled, enabled;

  @override
  State<EngineSwitch> createState() => _EngineSwitchState();
}

class _EngineSwitchState extends State<EngineSwitch> with SingleTickerProviderStateMixin {
  static const _side = 100.0, _h = 34.0, _pad = 3.0;
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  int _burstIndex = 0;
  static int _index(String e) => e == 'device' ? 0 : (e == 'whisper' ? 1 : 2);

  Color get ink => widget.ink;
  Color get paper => widget.paper;
  String get engine => widget.engine;
  bool get enabled => widget.enabled;

  @override
  void didUpdateWidget(EngineSwitch old) {
    super.didUpdateWidget(old);
    if (old.engine != widget.engine) {
      _burstIndex = _index(widget.engine);
      _burst.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _select(String value) {
    HapticFeedback.selectionClick(); // real haptics on Android/iOS builds
    switchFeedback(); // web: vibrate on Android Chrome, faint click elsewhere
    widget.onChanged(value);
  }

  Widget _option(String value, IconData icon, String label, bool optionEnabled) {
    final selected = engine == value;
    return Expanded(
      child: GestureDetector(
        key: ValueKey('engine-$value'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled && optionEnabled && !selected ? () => _select(value) : null,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: selected ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: Icon(icon, size: 15, color: selected ? paper : ink.withValues(alpha: optionEnabled ? 0.75 : 0.3)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.6,
                  color: selected ? paper : ink.withValues(alpha: optionEnabled ? 0.75 : 0.3),
                ),
                child: Text(label),
              ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hint = engine == 'whisper'
        ? 'On-device: private, no internet after the first download'
        : engine == 'gemini'
            ? 'Gemini: stronger Hindi/Hinglish, free tier with limits, audio goes to Google'
            : 'Cloud: starts instantly, needs internet';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: _side * 3 + _pad * 2,
            height: _h,
            padding: const EdgeInsets.all(_pad),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_h / 2),
              border: Border.all(color: ink.withValues(alpha: 0.25)),
              color: paper.withValues(alpha: 0.7),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  alignment: Alignment(_index(engine) - 1.0, 0),
                  child: Container(
                    width: _side,
                    height: _h - _pad * 2,
                    decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(_h / 2)),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _burst,
                      builder: (context, _) => CustomPaint(
                        painter: _BurstPainter(_burst.value, _burstIndex, _side, widget.accent),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _option('device', Icons.cloud_outlined, 'Cloud', widget.cloudEnabled),
                    _option('whisper', Icons.phone_iphone, 'On-device', true),
                    _option('gemini', Icons.auto_awesome, 'Gemini', true),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            hint,
            key: ValueKey(hint),
            style: TextStyle(fontSize: 10.5, letterSpacing: 0.4, color: ink.withValues(alpha: 0.55)),
          ),
        ),
      ],
    );
  }
}

/// Small burst of rays and a ring that radiates from the side that was just selected.
class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.index, this.side, this.color);
  final double t, side;
  final int index;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final c = Offset(side * (index + 0.5), size.height / 2);
    final fade = 1 - t;
    final ease = Curves.easeOutCubic.transform(t);
    final ray = Paint()
      ..color = color.withValues(alpha: fade)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi * 2 / 12;
      final r0 = 14 + 22 * ease;
      final r1 = r0 + 7 * fade;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * r1, ray);
    }
    canvas.drawCircle(
      c,
      10 + 34 * ease,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.5 * fade),
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.index != index;
}
