library;

import 'package:flutter/material.dart';

/// Dark palette — ELITE OBSIDIAN V1.0 accents (blue action + gold
/// achievement) on a **neutral** dark foundation.
///
/// The neutral values below are not chosen by eye: they are sampled from the
/// reference capture the matches screen is being matched against — pure
/// black page, `#2F2F2F` card, `#383838` raised control. The violet
/// foundation this replaces (`#07050D` / `#181326` / `#1D1730` / `#241C3A`)
/// tinted every surface in the app and was the single largest visual gap
/// left after the metric pass (`29_card_metrics_parity`). Accent, semantic
/// and achievement colors are deliberately untouched — only the neutral
/// ramp and the two grey text tones move, so the app keeps its identity.
abstract final class AppColors {
  static const Color background = Color(0xFF000000);
  static const Color backgroundElevated = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF2F2F2F);
  static const Color surfaceElevated = Color(0xFF383838);
  static const Color surfaceHigh = Color(0xFF424242);

  static const Color primary = Color(0xFF2F6BFF);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF5B8BFF);

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
  // Sampled from the same capture: secondary label text reads near-white,
  // muted label text ~#9D9D9D. The violet-tinted greys they replace read
  // markedly darker and cooler against the new neutral surfaces.
  static const Color textSecondary = Color(0xFFE3E3E3);
  static const Color textMuted = Color(0xFF9D9D9D);

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
