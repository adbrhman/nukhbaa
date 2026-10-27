/// The selected "make it double" button, through the real matches screen in
/// both themes: its bolt reaches 3:1 and its label 7:1 on both ends of
/// the blue gradient, and its gold rim 3:1 on the card. The bolt was gold
/// until the colour audit of 2026-10-15 -- 1.1:1 on the light blue (the
/// owner's screenshot: a bolt hardly there) and 2.8:1 on the dark one.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

CurrentMonthFixturesHarness _harness() =>
    buildCurrentMonthFixturesHarness((request) async {
      final String path = request.url.path;
      if (path == '/feed/current-month-fixtures') {
        return okJsonList([sampleFeedItem.toJson()]);
      }
      if (path == '/me/fixture-predictions' || path == '/teams') {
        return okJsonList(const []);
      }
      if (path == '/seasons/s-1/fixtures/f-1/prediction') {
        final Map<String, Object?> sent =
            jsonDecode(request.body) as Map<String, Object?>;
        return okJsonObject({
          'schema_version': 1,
          'id': 'fp-1',
          'participant_id': 'part-1',
          'fixture_id': 'f-1',
          'submitted_at': '2026-09-04T10:00:00.000Z',
          'home_goals': sent['home_goals'],
          'away_goals': sent['away_goals'],
          'is_double': sent['is_double'],
        });
      }
      return okJsonList(const []);
    });

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    testWidgets('$name: the selected double button reads on its blue', (
      tester,
    ) async {
      final CurrentMonthFixturesHarness harness = _harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          retry: (retryCount, error) => null,
          child: MaterialApp(
            theme: theme,
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const CurrentMonthFixturesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder button = find.byKey(
        const Key('currentMonthFixtures.double.f-1'),
      );
      await tester.tap(button);
      // Past the auto-save's debounce, so the save lands before the end.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final AppTokens t = theme.extension<AppTokens>()!;
      final Icon bolt = tester.widget<Icon>(
        find.descendant(of: button, matching: find.byIcon(Icons.bolt_rounded)),
      );
      final BoxDecoration fill = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: button,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .map((AnimatedContainer box) => box.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((BoxDecoration d) => d.gradient != null);
      final List<Color> blues = (fill.gradient! as LinearGradient).colors;
      final Color label = tester
          .widget<Text>(
            find.descendant(of: button, matching: find.byType(Text)),
          )
          .style!
          .color!;
      for (final Color blue in blues) {
        expect(
          _contrast(bolt.color!, blue),
          greaterThanOrEqualTo(3),
          reason: '$name: the bolt on $blue',
        );
        expect(
          _contrast(label, blue),
          greaterThanOrEqualTo(7),
          reason: '$name: the label on $blue',
        );
      }
      expect(
        _contrast(fill.border!.top.color, t.surface),
        greaterThanOrEqualTo(3),
        reason: '$name: the gold rim on the card',
      );
    });
  }

  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    testWidgets('$name: script 162: the unselected double and the ranking '
        'icon are secondary grey -- gold is kept for a reward', (tester) async {
      final CurrentMonthFixturesHarness harness = _harness();
      addTearDown(harness.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          retry: (retryCount, error) => null,
          child: MaterialApp(
            theme: theme,
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const CurrentMonthFixturesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final AppTokens t = theme.extension<AppTokens>()!;
      final Finder button = find.byKey(
        const Key('currentMonthFixtures.double.f-1'),
      );
      expect(button, findsOneWidget);
      final Icon bolt = tester.widget<Icon>(
        find.descendant(of: button, matching: find.byIcon(Icons.bolt_outlined)),
      );
      final Color label = tester
          .widget<Text>(
            find.descendant(of: button, matching: find.byType(Text)),
          )
          .style!
          .color!;
      final BoxDecoration frame = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: button,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .map((AnimatedContainer box) => box.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(label, t.textSecondary);
      expect(bolt.color, t.textSecondary);
      expect(frame.border!.top.color, t.controlBorder);
      expect(
        _contrast(label, t.surface),
        greaterThanOrEqualTo(7),
        reason: '$name: the label on the card',
      );
      expect(
        _contrast(frame.border!.top.color, t.surface),
        greaterThanOrEqualTo(3),
        reason: '$name: the outline on the card',
      );
      final Icon ranking = tester.widget<Icon>(
        find.byIcon(Icons.leaderboard_rounded),
      );
      expect(ranking.color, t.textSecondary);
    });
  }
}
