/// Audit L-16: "نقاطي" showed the gap to the leader twice, under two names.
/// The second tile now counts the exact calls -- through the real
/// [MyPointsScreen] with its reads given.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/history/prediction_history_providers.dart';
import 'package:mobile/features/leaderboards/leaderboards_providers.dart';
import 'package:mobile/features/record/my_points_screen.dart';
import 'package:mobile/features/record/season_record_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

const String _season = 's-10';

void main() {
  testWidgets('the gap is shown once; exact calls have their own tile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mySeasonRecordsProvider.overrideWith(
            (ref) async => const <MySeasonRecordDto>[
              MySeasonRecordDto(
                competitionId: 'c-1',
                competitionName: 'Monthly',
                seasonId: _season,
                seasonLabel: '10/2026',
                startAt: '2026-10-01T00:00:00.000Z',
                endAt: '2026-11-01T00:00:00.000Z',
                rank: 12,
                totalPoints: 45,
                exactCount: 14,
                settledCount: 110,
              ),
            ],
          ),
          fixtureLeaderboardProvider(_season).overrideWith(
            (ref) async => const FixtureLeaderboardDto(
              seasonId: _season,
              entries: <FixtureLeaderboardEntryDto>[
                FixtureLeaderboardEntryDto(
                  rank: 1,
                  participantId: 'p-top',
                  displayName: 'Top',
                  totalPoints: 60,
                  fixturesScored: 115,
                ),
                FixtureLeaderboardEntryDto(
                  rank: 12,
                  participantId: 'p-me',
                  displayName: 'Me',
                  totalPoints: 45,
                  fixturesScored: 111,
                  exactCount: 14,
                  decidedCount: 110,
                ),
              ],
            ),
          ),
          myFixturePredictionsProvider.overrideWith(
            (ref) async => const <FixturePredictionDto>[
              FixturePredictionDto(
                id: 'fp-1',
                participantId: 'p-me',
                fixtureId: 'f-1',
                seasonId: _season,
                submittedAt: '2026-10-02T10:00:00.000Z',
                homeGoals: 1,
                awayGoals: 0,
                isDouble: false,
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('ar'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const MyPointsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

    expect(find.text(l10n.myPointsLeaderGap), findsOneWidget);
    expect(find.text(l10n.myPointsNeededForFirst), findsNothing);
    // The gap, 15 points, once.
    expect(find.text(l10n.pointsAbbreviated(15)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('myPoints.exactHits')),
        matching: find.text('14'),
      ),
      findsOneWidget,
    );
  });
}
