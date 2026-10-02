import 'package:flutter/material.dart';

const _ink = Color(0xFF2B2A28);

/// Solid whiteboard-style "island" for the board controls, like Excalidraw's toolbars: opaque
/// white, a thin ink edge and a very light shadow. No blur, no transparency.
class BoardBar extends StatelessWidget {
  const BoardBar({
    super.key,
    required this.child,
    this.radius = 14,
    this.padding = const EdgeInsets.all(5),
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _ink.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: _ink.withValues(alpha: .12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Tool button inside a [BoardBar]: 44px tall (comfortable tap target), flat, with a solid ink
/// fill for the active tool and a light grey press state.
class BoardButton extends StatefulWidget {
  const BoardButton({
    super.key,
    this.label,
    this.icon,
    this.tooltip,
    required this.onPressed,
    this.on = false,
  }) : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool on;

  @override
  State<BoardButton> createState() => _BoardButtonState();
}

class _BoardButtonState extends State<BoardButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fg = widget.on ? Colors.white : _ink;
    final color = enabled ? fg : fg.withValues(alpha: .32);
    final iconOnly = widget.label == null;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) Icon(widget.icon, size: 20, color: color),
        if (widget.icon != null && widget.label != null)
          const SizedBox(width: 6),
        if (widget.label != null)
          Flexible(
            child: Text(
              widget.label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
      ],
    );
    Widget b = Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip ?? widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
              maxHeight: 44,
            ),
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: widget.on
                  ? _ink
                  : (_down ? const Color(0xFFE9E7E2) : Colors.transparent),
            ),
            child: Center(widthFactor: 1, child: content),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) b = Tooltip(message: widget.tooltip!, child: b);
    return b;
  }
}
