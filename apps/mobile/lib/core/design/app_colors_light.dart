library;

import 'package:flutter/material.dart';

/// Light palette -- the NUKHBA sheet's identity, inverted.
///
/// The sheet is a dark design and names no light values, so nothing here can
/// be copied from it. What CAN be carried over is the identity: the same
/// Blue `#2F6BFF` action, the same gold achievement, the same cool navy cast
/// in the neutrals. That is what this does.
///
/// It replaces a violet-tinted set (`#F7F5FA`, `#F1EDF7`, `#E6E0F0`) that
/// shared no hue with the dark mode's foundation -- the two modes did not
/// read as one product, which is the whole complaint.
///
/// Accents are DARKENED rather than reused. Bright Blue, Success and Danger
/// are tuned for white text on a dark card; on white they would be unreadable,
/// so each keeps its hue and loses its lightness.
abstract final class AppColorsLight {
  /// The neutrals: white cards on a cool off-white page, tinted toward the
  /// dark mode's Navy so both modes share one temperature.
  static const Color background = Color(0xFFF4F7FB);
  static const Color backgroundElevated = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFEDF2F9);
  static const Color surfaceHigh = Color(0xFFDFE7F1);

  /// The same action hue as dark mode, one step darker for contrast on white.
  static const Color primary = Color(0xFF1D4ED8);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color primaryLight = Color(0xFF2F6BFF);

  /// Gold at a lightness that holds >=4.5:1 for white content placed on it.
  static const Color gold = Color(0xFF8A6D00);
  static const Color goldDark = Color(0xFF6B5300);
  static const Color silver = Color(0xFF64748B);
  static const Color bronze = Color(0xFF9B5E1E);

  static const Color error = Color(0xFFD11A2B);
  static const Color errorContainer = Color(0xFFFDECEE);

  static const Color success = Color(0xFF00875A);
  static const Color successContainer = Color(0xFFE3F8F0);
  static const Color onSuccess = Color(0xFFFFFFFF);

  static const Color warning = Color(0xFF9A6400);
  static const Color warningContainer = Color(0xFFFDF3DE);
  static const Color onWarning = Color(0xFFFFFFFF);

  static const Color info = Color(0xFF0369A1);
  static const Color infoContainer = Color(0xFFE3F1FB);
  static const Color onInfo = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF0A1420);
  static const Color textSecondary = Color(0xFF3F4C5E);
  static const Color textMuted = Color(0xFF6B7889);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onGold = Color(0xFFFFFFFF);
  static const Color onError = Color(0xFFFFFFFF);

  /// A cool hairline, the light-mode counterpart of the dark blue stroke.
  static const Color border = Color(0x1F0A1420);

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
