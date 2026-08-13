import 'package:flutter/animation.dart';

/// Centralized animation timing — every animated transition in the app
/// (status changes, list-item entrances, refresh, expand/collapse, page
/// transitions) picks from this instead of inventing its own duration, so
/// motion feels like one consistent system rather than a pile of
/// independently-tuned effects. Durations are deliberately short: this is
/// a monitoring/ops tool, not a showcase app — motion should confirm a
/// change happened, never make the user wait to perceive it.
abstract final class AppMotion {
  /// A value/color/icon swap in place (a status dot, a metric number
  /// ticking) — barely perceptible, just enough to not look like a hard
  /// cut.
  static const fast = Duration(milliseconds: 140);

  /// A card/tile entering, a status badge cross-fading between two
  /// states, a sheet opening.
  static const medium = Duration(milliseconds: 220);

  /// A full-screen transition or a larger layout reflow (e.g. a section
  /// appearing/disappearing).
  static const slow = Duration(milliseconds: 320);

  /// The default easing for state changes — quick to start, gentle
  /// landing; reads as responsive without overshoot/bounce, which would
  /// undercut the "serious tool" feel.
  static const curve = Curves.easeOutCubic;

  /// For anything entering/leaving the screen (appearing list rows,
  /// dismissible sheets) — slightly more pronounced deceleration than
  /// [curve] so entrances feel settled, not abrupt.
  static const entranceCurve = Curves.easeOutQuart;
}
