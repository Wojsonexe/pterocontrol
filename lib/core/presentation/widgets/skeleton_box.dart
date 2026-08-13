import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';

/// A pulsing placeholder box — the building block for skeleton loading
/// states (server cards, dashboard metrics, backup rows, file rows), used
/// instead of a single centered spinner so the loading screen already has
/// the shape of the content that is about to arrive.
///
/// Implemented as a plain opacity pulse via [TweenAnimationBuilder]
/// looping through [_SkeletonPulse] rather than pulling in a `shimmer`
/// package — this app avoids new dependencies where a few lines of
/// stock Flutter animation API already do the job.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.borderRadius});

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return _SkeletonPulse(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.xs),
        ),
      ),
    );
  }
}

class _SkeletonPulse extends StatefulWidget {
  const _SkeletonPulse({required this.child});

  final Widget child;

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return Opacity(opacity: 0.6, child: widget.child);
    }
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.4, end: 1.0).chain(CurveTween(curve: Curves.easeInOut))),
      child: widget.child,
    );
  }
}
