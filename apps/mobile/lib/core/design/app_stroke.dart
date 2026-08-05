library;

/// Canonical border/stroke widths.
///
/// Every fixed border width used by shared UI components must come from
/// here so hairlines, card borders, and focus rings stay consistent and
/// auditable across the app.
abstract final class AppStroke {
  /// Dividers only — use sparingly.
  static const double hairline = 0.5;

  /// Default border for cards, chips, inputs.
  static const double regular = 1.0;

  /// Selected / active state border.
  static const double selected = 1.5;

  /// Keyboard-focus ring.
  static const double focus = 2.0;
}
