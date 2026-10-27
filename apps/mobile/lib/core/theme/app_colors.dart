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
///
/// Surfaces and the hairline later moved off the sheet on purpose
/// (2026-09-24): a near-black card on a navy page read as a hole rather than
/// a raised plane, and a blue stroke round every card spent the action colour
/// on decoration. Cards now sit one navy step above the page behind a quiet
/// navy hairline, and blue is kept for what the user can act on.
abstract final class AppColors {
  /// SHEET Navy -- the page. Cards sit only a shade off it and are separated
  /// by the blue stroke below, exactly as the sheet draws them.
  static const Color background = Color(0xFF071426);

  /// SHEET Obsidian -- app bar and bottom bar, deeper than the page so the
  /// chrome recedes instead of competing with the content.
  static const Color backgroundElevated = Color(0xFF000000);

  /// DERIVED -- every card: one navy step above [background], so a card
  /// reads as a raised plane. The sheet's Surface `#0A0A0A` sat below the
  /// page and read as a hole.
  // Lifted from 0xFF0D1B30 (2026-10-07): 1.07:1 against the page, the
  // cards melted into it and only their hairline set them apart.
  static const Color surface = Color(0xFF11223A);

  /// DERIVED -- one and two further steps up from [surface], in the same
  /// navy hue, for raised controls and table headers.
  static const Color surfaceElevated = Color(0xFF14253D);
  static const Color surfaceHigh = Color(0xFF1C2F4B);

  /// SHEET Blue -- the action colour, one step deeper than the sheet's
  /// `#2F6BFF`: white on that measured 4.499:1, a hair under WCAG AA, and
  /// white is the label on every blue fill. `#2E6AFF` reads 4.54:1 and is
  /// not a visible change.
  // Script 162 (2026-10-27, the owner's colour decision): the logo's own
  // hue (209-211) at WCAG AAA. On the navy a light blue fill carries navy
  // ink at 10.0:1 and stands 9.6:1 off the page; the logo blue carried
  // white at 4.52:1 only (AA). Was #2E6AFF, a second blue the logo never
  // used.
  static const Color primary = Color(0xFF84C0FF);

  /// DERIVED -- the container depth of [primary] in the logo's hue: white
  /// reads 7.04:1 on it.
  static const Color primaryDark = Color(0xFF135A9E);

  /// DERIVED -- the highlight and the far end of the action gradient: navy
  /// ink reads 12.2:1 on it.
  static const Color primaryLight = Color(0xFFA8D3FF);

  /// DERIVED -- blue as TEXT. [primary] carries white at 4.5:1 as a fill but
  /// reads only 3.8-4.1:1 as text on the navy surfaces, and [primaryLight]
  /// drops under 4.5:1 on a raised surface or a blue wash. This one holds
  /// 5:1 or better on every dark surface and wash, so blue labels and
  /// figures meet WCAG AA wherever they sit.
  // Script 162: AAA -- 7:1 or better on every surface, the viewer row and
  // the bottom bar (was #66B0FF, 5.9:1 on the highest surface).
  static const Color primaryText = Color(0xFFA8D3FF);

  /// SHEET Gold -- achievement.
  // Script 162: a hair lighter than the sheet's #F5C451, 7.07:1 on its
  // own wash and 10:1 on its container (AAA).
  static const Color gold = Color(0xFFF6C85C);

  /// DERIVED -- the far end of the gold gradient and the tonal gold fill:
  /// [onGold] reads 7.0:1 on it (was #B8860B, 5.0:1).
  static const Color goldDark = Color(0xFFDBA00D);

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

  /// DERIVED -- danger as TEXT. [error] reads 4.4:1 on a raised surface and
  /// 3.8:1 on the highest, under AA for the small labels it marks (the live
  /// minute, a fall on the board); this lighter red holds 5.3:1 or better on
  /// every dark surface, its container and the blue viewer row.
  // Script 162: AAA, 7:1 on every surface (was #FF7A85, 4.8:1).
  static const Color errorText = Color(0xFFFFB3B9);

  /// DERIVED -- danger as a FILL under white text (the unread badge): white
  /// on [error] is 3.5:1, on this 5.4:1. The same red as the light theme's.
  // Script 162: white reads 7.8:1 (was #D11A2B, 5.4:1); at 7.0:1 the
  // survey measured the unread "9+" at 6.5:1 over the light bell.
  static const Color errorFill = Color(0xFFA3141F);

  /// SHEET Success.
  static const Color success = Color(0xFF19E68C);
  static const Color successContainer = Color(0xFF06291C);

  /// DERIVED -- success as text and badge content: the sheet's mint at
  /// less saturation, so a points badge no longer glares on the navy
  /// (2026-10-07). Fills that carry near-black content keep [success].
  // Script 162: AAA, 7:1 on every surface (was #5CCF9B, 6.2:1).
  static const Color successText = Color(0xFF7DD9AF);

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
  // Script 162: AAA, 7:1 on every surface (was #A8B5C7, 5.7:1).
  static const Color textMuted = Color(0xFFBEC8D5);

  /// Navy ink on the light blue [primary] fill and its gradient: 10:1.
  static const Color onPrimary = Color(0xFF04101C);
  static const Color onGold = Color(0xFF2A1E04);
  static const Color onError = Color(0xFFFFFFFF);

  /// DERIVED -- a quiet navy hairline. The surface step already lifts a card
  /// off the page; the line only finishes the edge, so it no longer spends
  /// the action blue on decoration.
  static const Color border = Color(0xFF22354F);

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

  /// DERIVED -- the gradient behind [onPrimary] ink, from the action blue
  /// UP to the highlight: navy reads 10.0:1 to 12.2:1 across it (AAA).
  static const LinearGradient actionGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );
}
