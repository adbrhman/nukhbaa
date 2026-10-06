/// The home page's live card through the real card, the real
/// `LeaderboardsApi` and a fake server: while a match the viewer predicted
/// is in play it shows the running score, what their prediction would earn
/// if it ended now, who leads their duel and their month place now and
/// then; it stays hidden when nothing they predicted is in play.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/widgets/live_home_card.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

String _minutesAgo(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();

final class _Server {
  _Server({required this.predicted, required this.standing});

  final bool predicted;
  final Map<String, Object?> standing;
  int liveReads = 0;

  Future<http.Response> handle(http.Request request) async {
    switch (request.url.path) {
      case '/feed/current-month-fixtures':
        return okJsonList([
          CurrentMonthFixtureItemDto(
            competitionId: 'c-1',
            competitionName: 'League',
            seasonLabel: '10/2026',
            fixture: SeasonFixtureCardDto(
              seasonId: 's-1',
              fixtureId: 'f-1',
              homeTeam: 'Arsenal',
              awayTeam: 'Chelsea',
              kickoffAt: _minutesAgo(30),
            ),
            liveHomeGoals: 1,
            liveAwayGoals: 0,
            liveMinute: 30,
          ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([
          if (predicted)
            const FixturePredictionDto(
              id: 'pr-1',
              participantId: 'p-me',
              fixtureId: 'f-1',
              submittedAt: '2026-10-06T12:00:00.000Z',
              homeGoals: 1,
              awayGoals: 0,
              isDouble: true,
            ).toJson(),
        ]);
      case '/seasons/s-1/live':
        liveReads++;
        return okJsonObject(standing);
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

const Map<String, Object?> _inPlay = {
  'schema_version': 1,
  'fixtures': [
    {
      'fixture_id': 'f-1',
      'home_goals': 1,
      'away_goals': 0,
      'minute': 63,
      'finished': false,
      'my_points': 6,
    },
  ],
  'duels': [
    {
      'fixture_id': 'f-1',
      'opponent_name': 'Khaled',
      'my_points': 6,
      'opponent_points': 0,
    },
  ],
  'rank_now': 5,
  'rank_if_ended': 2,
  'points_now': 3,
  'points_if_ended': 9,
  'players': 12,
};

Future<(_Server, List<int>)> _pump(
  WidgetTester tester, {
  bool predicted = true,
  Map<String, Object?> standing = _inPlay,
}) async {
  final _Server server = _Server(predicted: predicted, standing: standing);
  final List<int> opened = <int>[];
  final harness = buildCurrentMonthFixturesHarness(server.handle);
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              LiveHomeCard(onOpenMatches: () => opened.add(1)),
            ],
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  return (server, opened);
}

void main() {
  testWidgets('a match in play shows the score, the points, the duel and '
      'the place', (tester) async {
    final (_Server server, List<int> opened) = await _pump(tester);

    expect(server.liveReads, 1);
    expect(
      tester.widget<Text>(find.byKey(const Key('home.live.score.f-1'))).data,
      'أرسنال 1 - 0 تشيلسي · الدقيقة 63',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('home.live.points.f-1'))).data,
      contains('ونقاطك لو انتهت الآن: 6'),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('home.live.duel.f-1.0'))).data,
      'تتقدم على Khaled في المواجهة (6 - 0)',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('home.live.rank.s-1'))).data,
      'مركزك في الشهر 5، ولو انتهت الآن: المركز 2 من 12',
    );

    await tester.tap(find.byKey(const Key('home.live')));
    expect(opened, hasLength(1));
  });

  testWidgets('the standing is read again a minute later', (tester) async {
    final (_Server server, _) = await _pump(tester);
    expect(server.liveReads, 1);

    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(milliseconds: 250));

    expect(server.liveReads, 2);
  });

  testWidgets('a match the viewer did not predict shows nothing', (
    tester,
  ) async {
    final (_Server server, _) = await _pump(tester, predicted: false);

    expect(find.byKey(const Key('home.live')), findsNothing);
    expect(server.liveReads, 0);
  });

  testWidgets('nothing in play on the server shows nothing', (tester) async {
    await _pump(
      tester,
      standing: const {'schema_version': 1, 'fixtures': [], 'duels': []},
    );

    expect(find.byKey(const Key('home.live')), findsNothing);
  });

  group('lines', () {
    test('a duel behind and level', () {
      expect(
        liveDuelLine(
          const LiveDuelStandingDto(
            fixtureId: 'f',
            opponentName: 'Sara',
            myPoints: 0,
            opponentPoints: 3,
          ),
        ),
        'Sara يتقدم عليك في المواجهة (0 - 3)',
      );
      expect(
        liveDuelLine(
          const LiveDuelStandingDto(
            fixtureId: 'f',
            opponentName: 'Sara',
            myPoints: 0,
            opponentPoints: 0,
          ),
        ),
        'مواجهتك مع Sara متعادلة (0 - 0)',
      );
    });

    test('a viewer not yet on the board', () {
      expect(
        liveRankLine(
          const LiveStandingDto(
            fixtures: [],
            duels: [],
            rankIfEnded: 7,
            pointsNow: 0,
            pointsIfEnded: 3,
            players: 20,
          ),
        ),
        'لو انتهت الآن: المركز 7 من 20 في ترتيب الشهر',
      );
    });
  });
}
