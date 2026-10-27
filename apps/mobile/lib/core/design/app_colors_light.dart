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
  // Script 162 (2026-10-27): the logo's hue (209) at WCAG AAA -- white on
  // it 10.3:1, and as text 7:1 or better on every light surface and on
  // its own 14% wash. Was #1D4ED8, a second blue the logo never used.
  static const Color primary = Color(0xFF0D4273);
  static const Color primaryDark = Color(0xFF0A3458);

  /// The lighter end of the blue gradients: white still 7.0:1 on it.
  static const Color primaryLight = Color(0xFF135A9E);

  /// Gold at a lightness that holds >=4.5:1 for white content placed on it.
  // Script 162: AAA -- white on it 9.5:1, and 7:1 as text on every light
  // surface and on its own wash (was #755D00, 5.1:1).
  static const Color gold = Color(0xFF564400);

  /// Gold for decoration -- the podium's ring, the leader's medal: it reads
  /// as gold, where [gold] (tuned to carry white text) reads olive. 3.8:1 on
  /// white, enough for a non-text mark; never carries text (UI-32).
  static const Color goldAccent = Color(0xFFA87B00);
  static const Color goldDark = Color(0xFF4A3A00);

  /// Gold as a fill under dark content -- a selected chip, a tonal button,
  /// the day strip's badge: the dark theme's own goldenrod, so the two
  /// themes fill gold alike. [goldDark] under white read olive brown on the
  /// light surfaces (the owner's screenshots, colour audit CA-20).
  // Script 162: lifted from #B8860B (5.0:1) so [onGoldFill] reads 7.0:1.
  static const Color goldFill = Color(0xFFDBA00D);

  /// Content on [goldFill]: 7.0:1.
  static const Color onGoldFill = Color(0xFF2A1E04);
  static const Color silver = Color(0xFF64748B);
  static const Color bronze = Color(0xFF9B5E1E);

  static const Color error = Color(0xFFD11A2B);
  static const Color errorContainer = Color(0xFFFDECEE);

  /// Danger as TEXT: [error] drops to 4.3:1 on the highest surface and the
  /// blue viewer row; this holds 5.2:1 or better on every light surface.
  // Script 162: AAA, 7:1 on every light surface (was #B42318, 5.3:1).
  static const Color errorText = Color(0xFF8A1A12);

  /// Danger as a FILL under white text (the unread badge, a destructive
  /// confirm): 7.8:1, the same red as the dark theme's.
  static const Color errorFill = Color(0xFFA3141F);

  static const Color success = Color(0xFF00875A);
  static const Color successContainer = Color(0xFFE3F8F0);

  /// Success as TEXT: [success] is 4.1:1 on its own container and 3.7:1 on
  /// the viewer row; this holds 5.2:1 or better on every light surface.
  // Script 162: AAA, 7:1 on every light surface (was #006B47, 5.3:1).
  static const Color successText = Color(0xFF004F35);
  static const Color onSuccess = Color(0xFFFFFFFF);

  static const Color warning = Color(0xFF9A6400);
  static const Color warningContainer = Color(0xFFFDF3DE);
  static const Color onWarning = Color(0xFFFFFFFF);

  static const Color info = Color(0xFF0369A1);
  static const Color infoContainer = Color(0xFFE3F1FB);
  static const Color onInfo = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF0A1420);
  // Script 162: AAA -- 7:1 or better on every light surface and the viewer
  // row (were #3F4C5E and #596473, 7.0:1 and 4.8:1 there).
  static const Color textSecondary = Color(0xFF2C3747);
  static const Color textMuted = Color(0xFF3F4753);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onGold = Color(0xFFFFFFFF);
  static const Color onError = Color(0xFFFFFFFF);

  /// A quiet cool hairline, as light as the dark theme's (about 1.4:1 on a
  /// card). At 50% of the text colour it outlined every card and divider
  /// in grey (UI-19). Controls keep their 3:1 outline in `controlBorder`.
  static const Color border = Color(0xFFD3DCE7);

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

  /// The gradient behind white text: white reads 10.3:1 to 12.8:1 across it.
  static const LinearGradient actionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryDark],
  );
}
