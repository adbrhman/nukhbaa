/// A finished prediction that earned points offers "share your hit": the
/// preview card shows the logo, the call against the final score, the
/// server's points and the viewer's place in the month -- through the real
/// [PredictionHistoryScreen] and the real scores, board and referral reads.
/// A prediction that earned nothing offers no share.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/history/exact_hit_share.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/prediction_harness.dart' as ph;

const String _fixture = 'f-hit';
const Key _share = Key('history.shareHit.fp-hit');

FixturePredictionDto _call({required bool isDouble}) => FixturePredictionDto(
  id: 'fp-hit',
  participantId: 'part-1',
  fixtureId: _fixture,
  seasonId: 's-1',
  submittedAt: '2026-09-01T10:00:00.000Z',
  homeGoals: 2,
  awayGoals: 1,
  isDouble: isDouble,
);

http.Response _scores(int points) => ph.okJsonObject(
  FixtureScoresDto(
    fixtureId: _fixture,
    scores: <ParticipantFixtureScoreDto>[
      ParticipantFixtureScoreDto(
        fixtureId: _fixture,
        participantId: 'part-1',
        rulesetVersion: 1,
        grade: points > 0 ? 'exact_scoreline' : 'incorrect',
        points: points,
      ),
    ],
    resultHomeGoals: points > 0 ? 2 : 0,
    resultAwayGoals: points > 0 ? 1 : 0,
  ).toJson(),
);

Future<void> _pump(
  WidgetTester tester, {
  required FixturePredictionDto prediction,
  required int points,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = ph.buildPredictionHarness((request) async {
    final String path = request.url.path;
    if (path == '/me/fixture-predictions') {
      return ph.okJsonList(<Object?>[prediction.toJson()]);
    }
    if (path == '/seasons/s-1/fixtures/$_fixture/scores') {
      return _scores(points);
    }
    if (path == '/seasons/s-1/fixture-leaderboard') {
      return ph.okJsonObject(
        const FixtureLeaderboardDto(
          seasonId: 's-1',
          entries: <FixtureLeaderboardEntryDto>[
            FixtureLeaderboardEntryDto(
              rank: 5,
              participantId: 'part-1',
              displayName: 'أحمد',
              totalPoints: 30,
              fixturesScored: 10,
            ),
          ],
        ).toJson(),
      );
    }
    if (path == '/me/referral') {
      return ph.okJsonObject(
        const ReferralSummaryDto(
          code: 'GC9HAERG',
          monthPoints: 0,
          seasonPoints: 0,
          invitedCount: 0,
          pendingCount: 0,
          monthCap: 20,
        ).toJson(),
      );
    }
    return ph.okJsonList(const <Object?>[]);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        currentMonthFixturesByIdProvider.overrideWithValue(
          const AsyncData<Map<String, SeasonFixtureCardDto>>({
            _fixture: SeasonFixtureCardDto(
              seasonId: 's-1',
              fixtureId: _fixture,
              homeTeam: 'Real Madrid',
              awayTeam: 'Barcelona',
              kickoffAt: '2026-09-02T19:00:00.000Z',
              leagueName: 'الدوري الإسباني',
            ),
          }),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PredictionHistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a double that hit opens a card with the points and the rank', (
    tester,
  ) async {
    await _pump(tester, prediction: _call(isDouble: true), points: 6);
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

    expect(find.byKey(_share), findsOneWidget);
    await tester.ensureVisible(find.byKey(_share));
    await tester.tap(find.byKey(_share));
    await tester.pumpAndSettle();

    expect(find.byType(ExactHitCard), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('shareHit.title'))).data,
      l10n.shareHitDoubleTitle,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('shareHit.points'))).data,
      '⚡🔥 ${l10n.shareHitPoints(6)}',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('shareHit.rank'))).data,
      l10n.shareHitRank(5),
    );
    expect(find.byKey(const Key('shareHit.share')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shareHit.close')));
    await tester.pumpAndSettle();
    expect(find.byType(ExactHitCard), findsNothing);
  });

  testWidgets('a prediction that earned nothing offers no share', (
    tester,
  ) async {
    await _pump(tester, prediction: _call(isDouble: false), points: 0);

    expect(find.byKey(_share), findsNothing);
  });
}
