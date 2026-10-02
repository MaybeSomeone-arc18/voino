import 'package:flutter/material.dart';

/// Minimal two-way switch between cloud speech ('device') and on-device Whisper ('whisper').
/// A pill slides between the two sides with a small overshoot, icons scale up on the active
/// side and the hint line cross-fades.
class EngineSwitch extends StatelessWidget {
  const EngineSwitch({
    super.key,
    required this.engine,
    required this.onChanged,
    required this.ink,
    required this.paper,
    this.cloudEnabled = true,
    this.enabled = true,
  });

  final String engine; // 'device' (cloud) | 'whisper' (on-device)
  final ValueChanged<String> onChanged;
  final Color ink, paper;
  final bool cloudEnabled, enabled;

  static const _side = 112.0, _h = 34.0, _pad = 3.0;

  Widget _option(String value, IconData icon, String label, bool optionEnabled) {
    final selected = engine == value;
    return Expanded(
      child: GestureDetector(
        key: ValueKey('engine-$value'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled && optionEnabled && !selected ? () => onChanged(value) : null,
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
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.6,
                  color: selected ? paper : ink.withValues(alpha: optionEnabled ? 0.75 : 0.3),
                ),
                child: Text(label),
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
        : 'Cloud: starts instantly, needs internet';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: _side * 2 + _pad * 2,
            height: _h,
            padding: const EdgeInsets.all(_pad),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_h / 2),
              border: Border.all(color: ink.withValues(alpha: 0.25)),
              color: paper.withValues(alpha: 0.7),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  alignment: engine == 'device' ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    width: _side,
                    height: _h - _pad * 2,
                    decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(_h / 2)),
                  ),
                ),
                Row(
                  children: [
                    _option('device', Icons.cloud_outlined, 'Cloud', cloudEnabled),
                    _option('whisper', Icons.phone_iphone, 'On-device', true),
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
