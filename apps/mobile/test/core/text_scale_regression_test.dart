/// Larger system text must not break layouts that the text-scale probe
/// (43_text_scale_probe) caught breaking: the leaderboard's movement column
/// with a two-digit move, and the matches tab's day strip, whose fixed-height
/// chips overflowed already at today's 1.3 cap. Pumped through the real
/// [LeaderboardBoard] and the real [CurrentMonthFixturesScreen].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/leaderboards/widgets/leaderboard_board.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../support/current_month_fixtures_harness.dart';

const List<double> _scales = <double>[1.0, 1.3, 2.0];

Widget _scaled(double scale, Widget home) => MaterialApp(
  theme: AppTheme.dark,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  locale: const Locale('ar'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child ?? const SizedBox.shrink(),
  ),
  home: home,
);

/// A phone's width, but tall enough that the lazy list builds every row at
/// x2.0: a row the list never built cannot be checked for fitting (the
/// first run of this test failed on exactly that, not on an overflow).
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 7200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  for (final double scale in _scales) {
    testWidgets('leaderboard: two-digit moves fit at x$scale', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: _scaled(
            scale,
            Scaffold(
              body: LeaderboardBoard(
                keyPrefix: 'reg',
                myParticipantId: 'p-5',
                showHeader: true,
                entries: <BoardEntry>[
                  for (int i = 0; i < 10; i++)
                    BoardEntry(
                      participantId: 'p-$i',
                      rank: i + 1,
                      displayName: 'لاعب رقم ${i + 1}',
                      points: 120 - i * 7,
                      pointsLabel: '${120 - i * 7}',
                      matchesCount: 40 - i,
                      accuracyPercent: i == 4 ? 100 : 30 + i,
                      movement: i.isEven ? 12 : -3,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('reg.movement.p-4')), findsOneWidget);
    });

    testWidgets('matches: the day strip and card fit at x$scale', (
      tester,
    ) async {
      _phone(tester);
      final harness = buildCurrentMonthFixturesHarness((request) async {
        final String path = request.url.path;
        if (path == '/feed/current-month-fixtures') {
          return okJsonList(<Object?>[sampleFeedItem.toJson()]);
        }
        if (path == '/seasons/s-1/fixtures/f-1/prediction-distribution') {
          return okJsonObject(const <String, Object?>{
            'schema_version': 1,
            'home_win_percentage': 68,
            'away_win_percentage': 32,
          });
        }
        if (path == '/me/fixture-predictions' || path == '/teams') {
          return okJsonList(const <Object?>[]);
        }
        throw StateError('Unexpected request: ${request.method} $path');
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          retry: (retryCount, error) => null,
          child: _scaled(scale, const CurrentMonthFixturesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('currentMonthFixtures.dayStrip')),
        findsOneWidget,
      );
    });
  }
}
