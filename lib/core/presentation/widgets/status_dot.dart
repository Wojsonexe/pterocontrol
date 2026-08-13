import 'package:flutter/material.dart';

/// The most compact status signal in the design system: a plain colored
/// dot, for contexts where even [AppStatusBadge]'s dense pill is too much
/// (a `ServerCard`'s title row, a list of many servers where every row
/// repeating a full text label would be noisy) — color still always pairs
/// with a text label placed by the caller right next to it, never alone,
/// same accessibility rule [AppStatusBadge] follows.
///
/// [pulsing] softly breathes the dot's opacity — reserved for "this is
/// happening *right now*" states (a server actually `running`, an
/// in-progress install), not every non-final state, so the motion stays a
/// meaningful signal instead of visual noise.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8, this.pulsing = false});

  final Color color;
  final double size;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    if (!pulsing) return dot;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return dot;
    return _Pulse(color: color, size: size);
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // A soft "halo" ring expanding and fading behind a steady core
        // dot — reads as a heartbeat, not a blink.
        final ringScale = 1 + t * 1.8;
        final ringOpacity = (1 - t).clamp(0.0, 1.0) * 0.35;
        return SizedBox(
          width: widget.size * 3,
          height: widget.size * 3,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: ringScale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: ringOpacity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          ),
        );
      },
    );
  }
}
