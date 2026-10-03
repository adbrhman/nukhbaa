/// Every text-on-background pair the screens draw, measured from the real
/// [AppTheme] tokens in both themes -- docs/reviews/ui-audit-2026-10.md,
/// section 2. This is where cards read as one merged label (home, my
/// predictions, the board rows) are measured: textContrastGuideline cannot
/// match a merged label to its Text widgets.
///
/// Each pair names the widget that draws it. A pair that fails today is
/// skipped with its finding id until the fix lands; the rest hold the line.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_colors.dart';
import 'package:mobile/core/theme/app_theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [tint] at [alpha] over [under]: the washes badges and pills sit on.
Color _wash(Color tint, double alpha, Color under) =>
    Color.alphaBlend(tint.withValues(alpha: alpha), under);

/// One pair: foreground, what it sits on, the ratio it needs, and -- while
/// it fails -- the finding that tracks it.
typedef _Pair = ({String name, Color fg, Color bg, double min, String? skip});

List<_Pair> _pairs(AppTokens t) {
  final bool dark = t.isDark;
  // The match card's base: a hard-coded grey in the dark theme (UI-08).
  final Color card = dark ? const Color(0xFF2F2F2F) : t.surface;
  final Color navBar = _wash(t.backgroundElevated, 0.96, t.background);
  final Color viewerRow = _wash(t.primary, 0.14, t.surface);
  return <_Pair>[
    // Text that already holds -- the line the fixes must not cross.
    (
      name: 'body text on the page',
      fg: t.textPrimary,
      bg: t.background,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'secondary text on the highest surface',
      fg: t.textSecondary,
      bg: t.surfaceHigh,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'muted text on the highest surface',
      fg: t.textMuted,
      bg: t.surfaceHigh,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'bottom bar: inactive tab label (nukhbaa_shell.dart:283)',
      fg: t.textSecondary,
      bg: navBar,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'badge, primary tone (app_badge.dart:29)',
      fg: t.primaryText,
      bg: _wash(t.primary, 0.14, t.surface),
      min: 4.5,
      skip: null,
    ),
    (
      name: 'badge, gold tone (app_badge.dart:32)',
      fg: t.gold,
      bg: _wash(t.gold, 0.16, t.surface),
      min: 4.5,
      skip: null,
    ),
    (
      name: 'badge, muted tone (app_badge.dart:41)',
      fg: t.textMuted,
      bg: t.surfaceHigh,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'podium: gold rank pill (leaderboard_board.dart:589)',
      fg: t.gold,
      bg: _wash(t.gold, 0.16, t.surface),
      min: 4.5,
      skip: null,
    ),
    (
      name:
          'match card: secondary text on the card (fotmob_match_card.dart:'
          '763)',
      fg: t.textSecondary,
      bg: card,
      min: 4.5,
      skip: null,
    ),
    (
      name:
          'my predictions: a scoring verdict (prediction_history_screen.'
          'dart:497)',
      fg: t.success,
      bg: t.surface,
      min: 4.5,
      skip: null,
    ),
    // Text that fails today.
    (
      name: 'bottom bar: active tab label (nukhbaa_shell.dart:283)',
      fg: t.primaryLight,
      bg: navBar,
      min: 4.5,
      skip: dark ? null : 'UI-03: primaryLight is 4.49:1 on the light bar',
    ),
    (
      name:
          'day strip: yesterday/today/tomorrow badge (fixtures_date_bar.'
          'dart:231-241)',
      fg: AppColors.onBronze,
      bg: t.gold,
      min: 4.5,
      skip: dark ? null : 'UI-02: fixed dark text on the light gold, 2.86:1',
    ),
    (
      name:
          'day strip: the selected chip date line (fixtures_date_bar.dart:'
          '193-194)',
      fg: Color.alphaBlend(t.onPrimary.withValues(alpha: 0.85), t.primary),
      bg: t.primary,
      min: 4.5,
      skip: dark ? 'UI-02: white at 85% on the action blue, 3.73:1' : null,
    ),
    (
      name: 'unread badge: label on its fill (home_screen.dart:479)',
      fg: dark ? AppColors.onError : t.onPrimary,
      bg: t.error,
      min: 4.5,
      skip: dark ? 'UI-05: white on the dark error red, 3.51:1' : null,
    ),
    (
      name: 'badge, success tone (app_badge.dart:33-36)',
      fg: t.primaryLight,
      bg: _wash(t.primary, 0.14, t.surface),
      min: 4.5,
      skip: 'UI-06: blue on a blue wash, 4.35:1 dark / 3.61:1 light',
    ),
    (
      name: 'badge, danger tone (app_badge.dart:37-40)',
      fg: t.error,
      bg: _wash(t.error, 0.14, t.surface),
      min: 4.5,
      skip: 'UI-06: 4.37:1 dark / 4.28:1 light',
    ),
    (
      name:
          'home overview card: title on the gradient start '
          '(home_screen.dart:529)',
      fg: t.onPrimary,
      bg: t.primaryLight,
      min: 4.5,
      skip: 'UI-07: white on primaryLight, 3.42:1 dark / 4.50- light',
    ),
    (
      name:
          'match card: the live dot label and minute '
          '(fotmob_match_card.dart:1208, 1230)',
      fg: t.error,
      bg: card,
      min: 4.5,
      skip: dark ? 'UI-08: the danger red on the grey card, 3.82:1' : null,
    ),
    (
      name:
          "match card: the everyone's-predictions button "
          '(fotmob_match_card.dart:1556)',
      fg: t.primary,
      bg: card,
      min: 4.5,
      skip: dark
          ? 'UI-08: the action blue as text on the grey card, 2.95:1'
          : null,
    ),
    (
      name: 'podium: silver rank pill (leaderboard_board.dart:589)',
      fg: t.silver,
      bg: _wash(t.silver, 0.16, t.surface),
      min: 4.5,
      skip: dark ? null : 'UI-13: light silver on its wash, 3.90:1',
    ),
    (
      name: 'podium: bronze rank pill (leaderboard_board.dart:589)',
      fg: t.bronze,
      bg: _wash(t.bronze, 0.16, t.surface),
      min: 4.5,
      skip: 'UI-13: bronze on its wash, 4.19:1 dark / 4.22:1 light',
    ),
    (
      name: 'board: a rise on the viewer row (leaderboard_board.dart:848)',
      fg: t.success,
      bg: viewerRow,
      min: 4.5,
      skip: dark ? null : 'UI-13: light green on the blue row, 3.66:1',
    ),
    (
      name: 'board: a fall on the viewer row (leaderboard_board.dart:848)',
      fg: t.error,
      bg: viewerRow,
      min: 4.5,
      skip: 'UI-13: red on the blue row, 4.24:1 dark / 4.33:1 light',
    ),
    // Outlines of controls (WCAG 1.4.11): 3:1.
    (
      name: 'admin text field outline on its fill (admin_ui_kit.dart:98-106)',
      fg: Color.alphaBlend(t.border, t.surfaceElevated),
      bg: t.surfaceElevated,
      min: 3,
      skip: dark ? 'UI-22: the hairline token as an outline, 1.24:1' : null,
    ),
    (
      name: 'segmented pill and day chip outline on the page',
      fg: t.controlBorder,
      bg: t.background,
      min: 3,
      skip: null,
    ),
  ];
}

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    final AppTokens tokens = theme.extension<AppTokens>()!;
    group('$name theme pairs', () {
      for (final _Pair pair in _pairs(tokens)) {
        test(pair.name, () {
          expect(
            _contrast(pair.fg, pair.bg),
            greaterThanOrEqualTo(pair.min),
            reason: '${pair.fg} on ${pair.bg}',
          );
        }, skip: pair.skip);
      }
    });
  }
}
