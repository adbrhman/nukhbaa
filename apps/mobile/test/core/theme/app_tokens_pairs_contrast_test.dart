/// Every text-on-background pair the screens draw, measured from the real
/// [AppTheme] tokens in both themes -- docs/reviews/ui-audit-2026-10.md,
/// section 2. This is where cards read as one merged label (home, my
/// predictions, the board rows) are measured: textContrastGuideline cannot
/// match a merged label to its Text widgets.
///
/// Each pair names the widget that draws it. A pair that fails today is
/// skipped with its finding id until the fix lands; the rest hold the line.
/// Batch 1 of the audit (2026-10-03) fixed UI-02, 03, 05, 06, 07, 08 and 13;
/// batch 4 the field outline (UI-22), the admin banners (UI-23) and the
/// switch (UI-31).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
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

List<_Pair> _pairs(AppTokens t, ThemeData theme) {
  final Color fieldOutline =
      theme.inputDecorationTheme.enabledBorder!.borderSide.color;
  final Color navBar = _wash(t.backgroundElevated, 0.96, t.background);
  final Color viewerRow = _wash(t.primary, 0.14, t.surface);
  return <_Pair>[
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
      name: 'bottom bar: inactive tab label (nukhbaa_shell.dart)',
      fg: t.textSecondary,
      bg: navBar,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'bottom bar: active tab label (UI-03)',
      fg: t.primaryText,
      bg: navBar,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'day strip: yesterday/today/tomorrow badge (UI-02)',
      fg: t.onGold,
      bg: t.gold,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'day strip: the selected chip date line (UI-02)',
      fg: t.onPrimary,
      bg: t.primary,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'unread badge: label on its fill (UI-05)',
      fg: t.onPrimary,
      bg: t.errorFill,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'badge, primary tone (app_badge.dart)',
      fg: t.primaryText,
      bg: _wash(t.primary, 0.14, t.surface),
      min: 4.5,
      skip: null,
    ),
    (
      name: 'badge, gold tone (app_badge.dart)',
      fg: t.gold,
      bg: _wash(t.gold, 0.16, t.surface),
      min: 4.5,
      skip: null,
    ),
    (
      name: 'badge, muted tone (app_badge.dart)',
      fg: t.textMuted,
      bg: t.surfaceHigh,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'badge, success tone (UI-06)',
      fg: t.successText,
      bg: t.successContainer,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'badge, danger tone (UI-06)',
      fg: t.errorText,
      bg: t.errorContainer,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'home overview card: white on the gradient start (UI-07)',
      fg: t.onPrimary,
      bg: t.actionGradient.colors.first,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'home overview card: white on the gradient end (UI-07)',
      fg: t.onPrimary,
      bg: t.actionGradient.colors.last,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'match card: secondary text on the card (UI-08)',
      fg: t.textSecondary,
      bg: t.surface,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'match card: the live label and minute (UI-08)',
      fg: t.errorText,
      bg: t.surface,
      min: 4.5,
      skip: null,
    ),
    (
      name: "match card: the everyone's-predictions button (UI-08)",
      fg: t.primaryText,
      bg: t.surface,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'match card: the saved check on its fill (UI-26)',
      fg: t.onSuccess,
      bg: t.success,
      min: 3,
      skip: null,
    ),
    (
      name: 'my predictions: a scoring verdict',
      fg: t.success,
      bg: t.surface,
      min: 4.5,
      skip: null,
    ),
    for (final (String medal, Color color) in <(String, Color)>[
      ('gold', t.goldAccent),
      ('silver', t.silver),
      ('bronze', t.bronze),
    ])
      (
        name: 'podium: $medal rank pill (UI-13)',
        fg: t.textPrimary,
        bg: _wash(color, 0.16, t.surface),
        min: 4.5,
        skip: null,
      ),
    (
      name: 'board: a rise on the viewer row (UI-13)',
      fg: t.successText,
      bg: viewerRow,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'board: a fall on the viewer row (UI-13)',
      fg: t.errorText,
      bg: viewerRow,
      min: 4.5,
      skip: null,
    ),
    // Outlines of controls (WCAG 1.4.11): 3:1.
    (
      name: 'text field outline on its fill, admin fields included (UI-22)',
      fg: Color.alphaBlend(fieldOutline, t.surfaceElevated),
      bg: t.surfaceElevated,
      min: 3,
      skip: null,
    ),
    (
      name: 'switch: the on thumb on the on track (UI-31)',
      fg: t.onPrimary,
      bg: t.primary,
      min: 3,
      skip: null,
    ),
    (
      name: 'switch: the off track outline on the page (UI-31)',
      fg: t.controlBorder,
      bg: t.background,
      min: 3,
      skip: null,
    ),
    (
      name: 'admin success banner text on its fill (UI-23)',
      fg: t.textPrimary,
      bg: t.successContainer,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'admin error banner text on its fill (UI-23)',
      fg: t.errorText,
      bg: t.errorContainer,
      min: 4.5,
      skip: null,
    ),
    (
      name: 'a crest plate rim on a card (team_logo.dart, UI-10)',
      fg: t.border,
      bg: t.surface,
      min: 1.2,
      skip: null,
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
      for (final _Pair pair in _pairs(tokens, theme)) {
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
