/// Gold as a fill -- a selected chip, a tonal button -- is the same
/// goldenrod in both themes, bright enough to read as gold. The light theme
/// filled with its dark text gold (#6B5300, #755D00) under white, which read
/// olive brown in the owner's screenshots (colour audit of 2026-10-15,
/// CA-20). Since script 162 gold means an achievement only: the day strip's
/// "today" badge is a neutral tag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixtures_date_bar.dart';
import 'package:mobile/l10n/app_localizations.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// In gold's hue, saturated and bright enough not to read olive.
void _expectGoldenrod(Color fill, Color gold, String what) {
  final HSVColor f = HSVColor.fromColor(fill);
  final double apart = (f.hue - HSVColor.fromColor(gold).hue).abs();
  expect(
    apart > 180 ? 360 - apart : apart,
    lessThanOrEqualTo(25),
    reason: '$what: hue ${f.hue.toStringAsFixed(0)}',
  );
  expect(f.saturation, greaterThanOrEqualTo(0.5), reason: '$what saturation');
  expect(
    f.value,
    greaterThanOrEqualTo(0.6),
    reason: '$what is ${f.value.toStringAsFixed(2)} bright: olive below 0.6',
  );
}

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    final AppTokens t = theme.extension<AppTokens>()!;
    final ColorScheme scheme = theme.colorScheme;

    test('$name: the gold fill is goldenrod; its content reads on it', () {
      _expectGoldenrod(scheme.secondaryContainer, t.goldAccent, 'fill');
      expect(
        _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
        greaterThanOrEqualTo(7),
        reason: '$name: content on the gold fill',
      );
    });

    testWidgets('$name: the day strip\'s "today" badge is neutral, not gold', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: FixturesDateStrip(
              selectedDay: DateTime.now(),
              onDaySelected: (DateTime day) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = lookupAppLocalizations(const Locale('ar'));
      final Finder today = find.text(l10n.fixturesDateToday);
      final Color fill =
          (tester
                      .widget<Container>(
                        find
                            .ancestor(
                              of: today,
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      expect(fill, t.surfaceHigh, reason: '$name: the "today" badge fill');
      expect(
        _contrast(tester.widget<Text>(today).style!.color!, fill),
        greaterThanOrEqualTo(7),
        reason: '$name: the "today" badge label',
      );
    });
  }
}
