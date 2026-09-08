library;

import 'package:flutter/material.dart';

/// Dark palette -- NUKHBA design sheet, adopted verbatim.
///
/// Ten values come straight off the sheet's colour system and are not to be
/// nudged by eye: Obsidian `#000000`, Navy `#071426`, Surface `#0A0A0A`,
/// Blue `#2F6BFF`, Bright Blue `#008BFF`, Gold `#F5C451`, Silver `#BFC9D6`,
/// Bronze `#C47A45`, Success `#19E68C`, Danger `#FF3B4D`. Each is marked
/// SHEET below. Everything else the app needs -- raised surfaces, containers,
/// "on" colours, warning and info -- is DERIVED from that same navy family,
/// because the sheet does not name them and inventing a second family is how
/// a palette drifts back apart.
///
/// This replaces the neutral grey ramp (`#2F2F2F` card, `#383838` raised)
/// that was sampled from a screenshot rather than a design. Greys read as an
/// absence of choice next to the sheet's navy; the app now carries one
/// foundation everywhere.
abstract final class AppColors {
  /// SHEET Navy -- the page. Cards sit only a shade off it and are separated
  /// by the blue stroke below, exactly as the sheet draws them.
  static const Color background = Color(0xFF071426);

  /// SHEET Obsidian -- app bar and bottom bar, deeper than the page so the
  /// chrome recedes instead of competing with the content.
  static const Color backgroundElevated = Color(0xFF000000);

  /// SHEET Surface -- every card.
  static const Color surface = Color(0xFF0A0A0A);

  /// DERIVED -- one and two steps up from [surface], tinted toward Navy so a
  /// raised control reads as lifted rather than merely lighter.
  static const Color surfaceElevated = Color(0xFF0E1A2E);
  static const Color surfaceHigh = Color(0xFF16253C);

  /// SHEET Blue -- the action colour.
  static const Color primary = Color(0xFF2F6BFF);

  /// DERIVED -- a pressed/container depth for [primary].
  static const Color primaryDark = Color(0xFF1D4ED8);

  /// SHEET Bright Blue -- the highlight: active tab, kickoff time, the accent
  /// that has to carry over a near-black card.
  static const Color primaryLight = Color(0xFF008BFF);

  /// SHEET Gold -- achievement.
  static const Color gold = Color(0xFFF5C451);

  /// DERIVED -- the far end of the gold gradient.
  static const Color goldDark = Color(0xFFB8860B);

  /// SHEET Silver and Bronze -- second and third place.
  static const Color silver = Color(0xFFBFC9D6);
  static const Color bronze = Color(0xFFC47A45);

  /// DERIVED -- legible text on a filled silver/bronze medal.
  static const Color onSilver = Color(0xFF0A1420);
  static const Color onBronze = Color(0xFF241205);

  /// SHEET Danger.
  static const Color error = Color(0xFFFF3B4D);

  /// DERIVED -- danger at page depth, so an error block sits on Navy without
  /// glowing.
  static const Color errorContainer = Color(0xFF2E0C13);

  /// SHEET Success.
  static const Color success = Color(0xFF19E68C);
  static const Color successContainer = Color(0xFF06291C);

  /// DERIVED -- Success is a bright mint; white on it is unreadable, so
  /// filled success surfaces carry near-black content.
  static const Color onSuccess = Color(0xFF04160F);

  /// DERIVED -- the sheet names no warning or info hue. Warning is pulled
  /// toward Gold and info toward Bright Blue, so neither introduces a hue the
  /// palette does not already own.
  static const Color warning = Color(0xFFF5A623);
  static const Color warningContainer = Color(0xFF2E2008);
  static const Color onWarning = Color(0xFF241703);

  static const Color info = Color(0xFF4FB6FF);
  static const Color infoContainer = Color(0xFF07243C);
  static const Color onInfo = Color(0xFF04101C);

  static const Color textPrimary = Color(0xFFFFFFFF);

  /// DERIVED -- the two grey text tones carry a slight cool cast now. Neutral
  /// greys look dirty on Navy; these are the same lightness, just in the
  /// palette's own hue.
  static const Color textSecondary = Color(0xFFD7E1EF);
  static const Color textMuted = Color(0xFF8B9CB5);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onGold = Color(0xFF2A1E04);
  static const Color onError = Color(0xFFFFFFFF);

  /// DERIVED -- a blue hairline, not a white one. With Surface this close to
  /// Navy, the stroke is what makes a card a card; the sheet draws exactly
  /// this, and a 6% white line would leave every card edgeless.
  static const Color border = Color(0x382F6BFF);

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
