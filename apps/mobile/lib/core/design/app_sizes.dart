library;

/// Canonical component / icon / control sizes.
///
/// Every fixed non-spacing dimension used by shared UI components must come
/// from here so sizing stays consistent and auditable across the app.
/// Spacing continues to live in [AppSpacing]; radii in [AppRadius].
abstract final class AppSizes {
  static const double iconXs = 16;
  static const double iconSm = 18;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 38;

  static const double controlSm = 40;
  static const double controlMd = 46;
  static const double controlLg = 52;

  static const double progressSm = 20;
  static const double progressStroke = 2.4;

  static const double minTouchTarget = 48;

  static const double brandMark = 72;

  static const double maxContentWidth = 600;
  static const double maxFormWidth = 460;
}
