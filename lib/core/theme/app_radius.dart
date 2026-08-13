/// Centralized corner-radius scale.
///
/// [full] is [double.infinity]: passed to [BorderRadius.circular] it
/// clamps to whatever the shape's own bounds allow, which is the correct,
/// idiomatic way to express "fully rounded regardless of size" (pill
/// shapes, circular indicators) without hand-computing a value large
/// enough for every possible box size.
///
abstract final class AppRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;

  /// Large, full-bleed surfaces — the console terminal panel and other
  /// standalone surfaces that should read as bigger than a card.
  static const double lg = 24;

  /// Hero surfaces — the Dashboard's overview card, bottom sheets' top
  /// corners — the single largest radius in the system, reserved for the
  /// one or two surfaces per screen that should read as *the* focal
  /// element.
  static const double xl = 28;
  static const double full = double.infinity;
}
