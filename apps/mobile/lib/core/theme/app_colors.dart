library;

import 'package:flutter/material.dart';

/// Dark palette — AZURE OBSIDIAN design system (blue action + gold
/// achievement, on an Obsidian dark foundation).
abstract final class AppColors {
  static const Color background = Color(0xFF07050D);
  static const Color backgroundElevated = Color(0xFF0A0811);
  static const Color surface = Color(0xFF181326);
  static const Color surfaceElevated = Color(0xFF1D1730);
  static const Color surfaceHigh = Color(0xFF241C3A);

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF60A5FA);

  static const Color gold = Color(0xFFF5C451);
  static const Color goldDark = Color(0xFFB8860B);
  static const Color silver = Color(0xFFC3CBD6);
  static const Color onSilver = Color(0xFF1B2430);
  static const Color bronze = Color(0xFFCD8A4E);
  static const Color onBronze = Color(0xFF2A1608);

  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFF3A151A);

  /// Semantic status colors — each an independent hue per the ELITE OBSIDIAN
  /// spec (violet = action, gold = achievement; success/warning/info are
  /// their own distinct colors, no longer aliased to primary/gold).
  static const Color success = Color(0xFF22C55E);
  static const Color successContainer = Color(0xFF14291D);
  static const Color onSuccess = Color(0xFFFFFFFF);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFF3A2A0E);
  static const Color onWarning = Color(0xFF2A1B04);

  static const Color info = Color(0xFF38BDF8);
  static const Color infoContainer = Color(0xFF122A3A);
  static const Color onInfo = Color(0xFF0B1220);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFC8C2D3);
  static const Color textMuted = Color(0xFF6F687D);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onGold = Color(0xFF2A1E04);
  static const Color onError = Color(0xFFFFFFFF);

  static const Color border = Color(0x0FFFFFFF);

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
