library;

import 'package:flutter/material.dart';

/// Light palette — neutral Slate/Zinc surfaces + calm Emerald accent.
abstract final class AppColorsLight {
  static const Color background = Color(0xFFF8FAFC);
  static const Color backgroundElevated = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF1F5F9);
  static const Color surfaceHigh = Color(0xFFE2E8F0);

  static const Color primary = Color(0xFF00794C);
  static const Color primaryDark = Color(0xFF00613D);
  static const Color primaryLight = Color(0xFF00A868);

  static const Color gold = Color(0xFFB77F17);
  static const Color goldDark = Color(0xFF8A6212);
  static const Color silver = Color(0xFF64748B);
  static const Color bronze = Color(0xFF9B5E1E);

  static const Color error = Color(0xFFDC2626);
  static const Color errorContainer = Color(0xFFFEF2F2);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onGold = Color(0xFFFFFFFF);
  static const Color onError = Color(0xFFFFFFFF);

  /// Semantic status colors. `success`/`warning` deliberately reuse the
  /// existing primary/gold hues (see design tokens addendum decision log)
  /// to avoid a second color competing visually with the medal gold.
  /// `info` is the one genuinely new hue - no blue exists elsewhere in
  /// this palette to repurpose.
  static const Color success = primary;
  static const Color successContainer = Color(0xFFD1FAE5);
  static const Color onSuccess = onPrimary;

  static const Color warning = gold;
  static const Color warningContainer = Color(0xFFFDF0D5);
  static const Color onWarning = onGold;

  static const Color info = Color(0xFF2563EB);
  static const Color infoContainer = Color(0xFFDBEAFE);
  static const Color onInfo = Color(0xFFFFFFFF);

  static const Color border = Color(0x140F172A);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundElevated, background],
  );
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary],
  );
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gold, goldDark],
  );
}
