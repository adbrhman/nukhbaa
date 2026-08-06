library;

import 'package:flutter/material.dart';

/// Dark palette — Slate neutrals + a single calm Emerald accent.
abstract final class AppColors {
  static const Color background = Color(0xFF0B0F17);
  static const Color backgroundElevated = Color(0xFF11161F);
  static const Color surface = Color(0xFF151B26);
  static const Color surfaceElevated = Color(0xFF1C2330);
  static const Color surfaceHigh = Color(0xFF272F3D);

  static const Color primary = Color(0xFF10B981);
  static const Color primaryDark = Color(0xFF059669);
  static const Color primaryLight = Color(0xFF34D399);

  static const Color gold = Color(0xFFE0B341);
  static const Color goldDark = Color(0xFFB88C22);
  static const Color silver = Color(0xFFC3CBD6);
  static const Color onSilver = Color(0xFF1B2430);
  static const Color bronze = Color(0xFFCD8A4E);
  static const Color onBronze = Color(0xFF2A1608);

  static const Color error = Color(0xFFF87171);
  static const Color errorContainer = Color(0xFF3A1D22);

  /// Semantic status colors. `success`/`warning` deliberately reuse the
  /// existing primary/gold hues (see design tokens addendum decision log)
  /// to avoid a second color competing visually with the medal gold.
  /// `info` is the one genuinely new hue — no blue exists elsewhere in
  /// this palette to repurpose.
  static const Color success = primary;
  static const Color successContainer = Color(0xFF102A22);
  static const Color onSuccess = onPrimary;

  static const Color warning = gold;
  static const Color warningContainer = Color(0xFF3A2E0E);
  static const Color onWarning = onGold;

  static const Color info = Color(0xFF60A5FA);
  static const Color infoContainer = Color(0xFF13233A);
  static const Color onInfo = Color(0xFF0B1220);

  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const Color onPrimary = Color(0xFF04140E);
  static const Color onGold = Color(0xFF2A1E04);
  static const Color onError = Color(0xFF2A0A0E);

  static const Color border = Color(0x14FFFFFF);

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
