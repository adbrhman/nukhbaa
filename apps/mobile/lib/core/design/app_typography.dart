library;

import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const String fontFamily = 'IBMPlexSansArabic';

  // No letterSpacing anywhere in the scale: tracking is applied between
  // glyphs, and in Arabic that pulls joined letters apart. Latin text reads
  // the same without it at these sizes.
  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w700),
    displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w700),
    displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
  );
}

/// The named steps of the type scale outside the Material roles above:
/// chips and badges, the match card's own measured sizes, small captions.
/// Every size in the app is one of these or a [AppTypography.textTheme]
/// role -- `test/core/design/font_size_scale_test.dart` rejects a bare
/// number -- so a size change is one edit here, not a search.
abstract final class AppFontSize {
  /// 9 px: the tightest badge text.
  static const double s9 = 9;

  /// 10 px: chip and badge labels.
  static const double s10 = 10;

  /// 11 px: small captions.
  static const double s11 = 11;

  /// 12 px: secondary lines and inline status.
  static const double s12 = 12;

  /// 13 px: team names and compact headers.
  static const double s13 = 13;

  /// 14 px: body-size emphasis.
  static const double s14 = 14;

  /// 15 px: a step between body and title.
  static const double s15 = 15;

  /// 16 px: titles inside cards.
  static const double s16 = 16;

  /// 18 px: a medal rank.
  static const double s18 = 18;

  /// 20 px: the score steppers' figures.
  static const double s20 = 20;

  /// 22 px: headings inside cards.
  static const double s22 = 22;

  /// 24 px: large headings.
  static const double s24 = 24;

  /// 26 px: the live score.
  static const double s26 = 26;
}
