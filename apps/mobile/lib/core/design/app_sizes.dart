library;

/// Canonical component / icon / control sizes.
///
/// Every fixed non-spacing dimension used by shared UI components must come
/// from here so sizing stays consistent and auditable across the app.
/// Spacing continues to live in [AppSpacing]; radii in [AppRadius].
abstract final class AppSizes {
  // ── Icon sizes ────────────────────────────────────────────────────────
  static const double iconInline = 14; // icon inside a badge/pill
  static const double iconXs = 16;
  static const double iconSm = 18;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 38; // brand mark glyph
  static const double iconState = 48; // empty/error state (compact)
  static const double iconStateLg = 56; // empty/error state (full page)

  // ── Control heights (buttons, inputs, rows) ───────────────────────────
  static const double controlSm = 40;
  static const double controlMd = 46;
  static const double controlLg = 52;

  // ── Inline progress indicator ─────────────────────────────────────────
  static const double progressSm = 20;
  static const double progressStroke = 2.4;

  // ── Minimum accessible touch target (Material / WCAG 2.5.5) ───────────
  static const double minTouchTarget = 48;

  // ── Avatars / marks ───────────────────────────────────────────────────
  static const double avatarSm = 44;
  static const double brandMark = 72;

  // ── Radii for fully-rounded pills ─────────────────────────────────────
  static const double pillRadius = 999;

  // ── Layout constraints ────────────────────────────────────────────────
  static const double maxContentWidth = 600;
  static const double maxFormWidth = 460;
  static const double maxAccountWidth = 480;
}
