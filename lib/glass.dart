import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Frosted "glass" capsule button, following Apple's Liquid Glass guidance: a translucent
/// functional layer with a blur, a thin light edge and a soft highlight, fully rounded (capsule)
/// so it sits concentric with the rounded bar around it. Use it for the few primary controls only,
/// never for content. Falls back to a solid fill when the system asks for higher contrast.
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.ink = const Color(0xFF2B2A28),
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary; // tinted, higher emphasis
  final Color ink;
  final double height;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final solid = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final enabled = widget.onPressed != null;
    final r = BorderRadius.circular(widget.height / 2);
    final ink = widget.ink;
    final fill = widget.primary
        ? ink.withValues(alpha: solid ? 1 : 0.86)
        : Colors.white.withValues(alpha: solid ? 1 : 0.5);
    final fg = widget.primary ? Colors.white : ink;
    final glass = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        color: fill,
        gradient: solid
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: widget.primary ? 0.16 : 0.45),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0, 0.6],
              ),
        border: Border.all(
          color: widget.primary ? Colors.white.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.9),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: enabled ? fg : fg.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: r,
                boxShadow: [
                  BoxShadow(color: ink.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: ClipRRect(
                borderRadius: r,
                child: solid ? glass : BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: glass),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
