library;

/// Canonical opacity values for interaction/overlay states.
///
/// Every non-1.0 alpha used by shared UI components must come from here so
/// disabled/pressed/hover/focus/scrim treatments stay consistent and
/// auditable across the app. Colors themselves still come from [AppTokens];
/// this only fixes the alpha applied on top of them.
abstract final class AppOpacity {
  /// Disabled content (buttons, inputs, chips).
  static const double disabled = 0.40;

  /// Press-state overlay drawn on top of an interactive surface.
  static const double pressed = 0.12;

  /// Hover-state overlay (web/desktop pointer only).
  static const double hover = 0.08;

  /// Background tint behind a keyboard-focus ring.
  static const double focus = 0.20;

  /// Modal scrim behind a bottom sheet or dialog — light theme.
  static const double scrimLight = 0.45;

  /// Modal scrim behind a bottom sheet or dialog — dark theme.
  static const double scrimDark = 0.60;

  /// Skeleton loader base fill.
  static const double skeletonBase = 0.06;

  /// Skeleton loader shimmer highlight.
  static const double skeletonHighlight = 0.14;

  /// Tint used for a status container fill (e.g. success/warning pill bg).
  static const double statusContainer = 0.12;

  /// Alpha used for a status container's border.
  static const double statusBorder = 0.28;

  /// Tint of a brand color washed into a card background gradient (e.g. the
  /// home/away team-color wash on a match card).
  static const double tint = 0.18;

  /// Alpha of a brand-color ambient glow/shadow behind a card.
  static const double glow = 0.22;
}
