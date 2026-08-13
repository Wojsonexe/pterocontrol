import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Wraps [child] in a one-shot fade-in, played once when this widget
/// first builds — the "content is arriving" entrance used by list rows
/// (`ServerCard` rows on Dashboard/Servers) so a freshly loaded list
/// feels like it settled into place rather than just appearing.
///
/// Opacity only, deliberately not also a slide/transform: a
/// [SlideTransition] wrapping a [Semantics]-bearing subtree inside a
/// scrolling [ListView] is a known trigger for a Flutter framework
/// semantics-tree assertion (`!semantics.parentDataDirty`) — reproduced
/// while building this exact screen. [FadeTransition] (opacity, no
/// transform) does not hit it, and a fade alone is already enough motion
/// for "content is arriving" — see `AppMotion`'s "short and functional"
/// brief.
///
/// Also deliberately driven purely by this widget's own
/// [AnimationController] (started synchronously in [initState]) rather
/// than a real-time per-index stagger (`Future.delayed`) — a real
/// `Timer` racing against `WidgetTester.pumpAndSettle`'s own
/// frame-pumping loop is its own source of flaky/hanging widget tests.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;

  /// Accepted for call-site readability (list position) but currently
  /// unused — every row animates in together. Kept as a parameter so
  /// call sites don't need to change if a cheap, frame-driven stagger is
  /// added later.
  final int index;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
    _fade = CurvedAnimation(parent: _controller, curve: AppMotion.entranceCurve);

    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _controller.value = reduceMotion ? 1 : 0;
    if (!reduceMotion) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: widget.child);
  }
}
