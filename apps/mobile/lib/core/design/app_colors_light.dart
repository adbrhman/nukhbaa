library;

import 'package:flutter/material.dart';

/// Light palette — ELITE OBSIDIAN V1.0, light-mode counterpart (violet
/// action + gold achievement on light neutral surfaces).
abstract final class AppColorsLight {
  static const Color background = Color(0xFFF7F5FA);
  static const Color backgroundElevated = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFF1EDF7);
  static const Color surfaceHigh = Color(0xFFE6E0F0);

  static const Color primary = Color(0xFF1D4ED8);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color primaryLight = Color(0xFF3B82F6);

  static const Color gold = Color(0xFFA16207);
  static const Color goldDark = Color(0xFF854D0E);
  static const Color silver = Color(0xFF64748B);
  static const Color bronze = Color(0xFF9B5E1E);

  static const Color error = Color(0xFFDC2626);
  static const Color errorContainer = Color(0xFFFEF2F2);

  static const Color success = Color(0xFF16A34A);
  static const Color successContainer = Color(0xFFDCFCE7);
  static const Color onSuccess = Color(0xFFFFFFFF);

  static const Color warning = Color(0xFFD97706);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color onWarning = Color(0xFFFFFFFF);

  static const Color info = Color(0xFF0284C7);
  static const Color infoContainer = Color(0xFFDBEAFE);
  static const Color onInfo = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF120E1A);
  static const Color textSecondary = Color(0xFF4A4358);
  static const Color textMuted = Color(0xFF716B80);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onGold = Color(0xFFFFFFFF);
  static const Color onError = Color(0xFFFFFFFF);

  static const Color border = Color(0x14120E1A);

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
