/// The day's challenge bar, through the real card over the real transport
/// in both themes: its fill reaches 3:1 on its track and on the card, as a
/// progress bar must. The dark theme's fill blue read 2.97:1 on the track
/// until the colour audit of 2026-10-15 (CA-18).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/gamification/daily_challenge_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/auth_harness.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

http.Response _okJson(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
  ]) {
    for (final bool complete in <bool>[false, true]) {
      testWidgets('$name: the bar ${complete ? 'complete' : 'on its way'} '
          'reads on its track and its card', (tester) async {
        final AuthHarness harness = buildAuthHarness((
          http.Request request,
        ) async {
          switch (request.url.path) {
            case '/me/daily-challenge':
              return _okJson(<String, Object?>{
                'schema_version': 1,
                'day': '2026-10-15',
                'total': 3,
                'predicted': complete ? 3 : 2,
                'complete': complete,
              });
            case '/me/streak':
              return _okJson(<String, Object?>{
                'schema_version': 1,
                'current': 2,
                'longest': 9,
              });
          }
          return http.Response('not found', 404);
        }, seedToken: 'jwt');
        addTearDown(harness.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: harness.overrides,
            child: MaterialApp(
              theme: theme,
              locale: const Locale('ar'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Scaffold(body: DailyChallengeCard(onOpenMatches: () {})),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final AppTokens t = theme.extension<AppTokens>()!;
        final Color fill = tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.descendant(
                  of: find.byKey(const Key('home.dailyChallenge')),
                  matching: find.byType(FractionallySizedBox),
                ),
                matching: find.byType(ColoredBox),
              ),
            )
            .color;
        for (final (String under, Color colour) in <(String, Color)>[
          ('track', t.surfaceHigh),
          ('card', t.surface),
        ]) {
          expect(
            _contrast(fill, colour),
            greaterThanOrEqualTo(3),
            reason:
                '$name: the bar on its $under is '
                '${_contrast(fill, colour).toStringAsFixed(2)}:1',
          );
        }
      });
    }
  }
}
