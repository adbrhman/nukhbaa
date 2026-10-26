/// The doubles that paid through the real predictions board, the real
/// `GET /me` and a fake server (2026-10-24): an admin sees a line for each
/// match whose doubles earned points, and the card names each player with
/// his points, or only their count with the names switched off. A double
/// that earned nothing and a plain exact call are left out, and a player
/// sees none of it.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/competition/team_identity.dart';
import 'package:mobile/features/fixture_prediction/widgets/double_hits_card.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

String _hoursAgo(int hours) =>
    DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String();

/// (participant, name, home goals, double, grade, points)
typedef _Call = (String, String, int, bool, String, int);

/// Liverpool 2-0 Brighton: Ali, Huda and Omar doubled 2-0 (6 each); Zaid
/// doubled 0-1 (nothing); Sara called 2-0 without a double (3).
const List<_Call> _calls = <_Call>[
  ('p-ali', 'Ali', 2, true, 'exact_scoreline', 6),
  ('p-huda', 'Huda', 2, true, 'exact_scoreline', 6),
  ('p-omar', 'Omar', 2, true, 'exact_scoreline', 6),
  ('p-zaid', 'Zaid', 0, true, 'incorrect', 0),
  ('p-sara', 'Sara', 2, false, 'exact_scoreline', 3),
];

Map<String, Object?> _prediction(_Call c) => FixturePredictionDto(
  id: 'pr-${c.$1}',
  participantId: c.$1,
  fixtureId: 'f-1',
  submittedAt: '2026-10-24T12:00:00.000Z',
  homeGoals: c.$3,
  awayGoals: 0,
  isDouble: c.$4,
  displayName: c.$2,
).toJson();

final class _Server {
  _Server({required this.role});

  final String role;
  final String kickoffAt = _hoursAgo(3);

  Future<http.Response> handle(http.Request request) async {
    switch (request.url.path) {
      case '/me':
        return okJsonObject(
          MeResponseDto(
            user: AuthenticatedUserDto(
              userId: 'u-1',
              role: role,
              status: 'active',
              displayName: 'Ali',
            ),
          ).toJson(),
        );
      case '/feed/current-month-fixtures':
        return okJsonList([
          CurrentMonthFixtureItemDto(
            competitionId: 'c-1',
            competitionName: 'League',
            seasonLabel: '10/2026',
            fixture: SeasonFixtureCardDto(
              seasonId: 's-1',
              fixtureId: 'f-1',
              homeTeam: 'Liverpool',
              awayTeam: 'Brighton',
              kickoffAt: kickoffAt,
            ),
          ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([_prediction(_calls.first)]);
      case '/seasons/s-1/fixtures/f-1/predictions':
        return okJsonList([for (final _Call c in _calls) _prediction(c)]);
      case '/seasons/s-1/fixtures/f-1/scores':
        return okJsonObject(
          FixtureScoresDto(
            fixtureId: 'f-1',
            scores: <ParticipantFixtureScoreDto>[
              for (final _Call c in _calls)
                ParticipantFixtureScoreDto(
                  fixtureId: 'f-1',
                  participantId: c.$1,
                  rulesetVersion: 3,
                  grade: c.$5,
                  points: c.$6,
                ),
            ],
          ).toJson(),
        );
      case '/seasons/s-1/fixtures/f-1/reactions':
        return okJsonObject(
          const PredictionReactionsDto(
            reactions: <PredictionReactionTallyDto>[],
          ).toJson(),
        );
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Future<void> _pump(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
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
        home: FixturePredictionsBoardPage(kickoffAt: server.kickoffAt),
      ),
    ),
  );
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

const Key _banner = Key('fixturePredictions.doubles.f-1');
const Key _card = Key('doubleHits.card');

void main() {
  testWidgets('an admin sees the doubles that paid, named with points', (
    tester,
  ) async {
    await _pump(tester, _Server(role: 'admin'));

    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.textContaining('مضاعفة ناجحة: 3 لاعبين'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_banner));
    await _frames(tester);
    expect(find.byKey(_card), findsOneWidget);
    for (final String id in <String>['p-ali', 'p-huda', 'p-omar']) {
      final Finder row = find.byKey(Key('doubleHits.player.$id'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('6')),
        findsOneWidget,
      );
    }
    expect(find.byKey(const Key('doubleHits.player.p-zaid')), findsNothing);
    expect(find.byKey(const Key('doubleHits.player.p-sara')), findsNothing);
    expect(find.byKey(const Key('doubleHits.count')), findsNothing);
    expect(find.byKey(const Key('doubleHits.share')), findsOneWidget);
  });

  testWidgets('the names switched off leave the count and the points', (
    tester,
  ) async {
    await _pump(tester, _Server(role: 'admin'));
    await tester.tap(find.byKey(_banner));
    await _frames(tester);

    await tester.tap(find.byKey(const Key('doubleHits.names')));
    await _frames(tester);

    expect(find.byKey(const Key('doubleHits.player.p-ali')), findsNothing);
    expect(
      find.descendant(of: find.byKey(_card), matching: find.text('Ali')),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('doubleHits.count'))).data,
      '3',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('doubleHits.each'))).data,
      'كل لاعب 6 نقاط',
    );
  });

  test('the share text names the players with their points, or not', () {
    const ResolvedTeamIdentity liverpool = ResolvedTeamIdentity(
      displayName: 'ليفربول',
    );
    const ResolvedTeamIdentity brighton = ResolvedTeamIdentity(
      displayName: 'برايتون',
    );
    final DoubleHits doubles = DoubleHits(
      fixtureId: 'f-1',
      home: liverpool,
      away: brighton,
      hits: doubleHitsOf(
        predictions: <FixturePredictionDto>[
          for (final _Call c in _calls)
            FixturePredictionDto.fromJson(_prediction(c)),
        ],
        scores: <String, ParticipantFixtureScoreDto>{
          for (final _Call c in _calls)
            c.$1: ParticipantFixtureScoreDto(
              fixtureId: 'f-1',
              participantId: c.$1,
              rulesetVersion: 3,
              grade: c.$5,
              points: c.$6,
            ),
        },
        unnamed: 'لاعب',
      ),
    );
    const String sentence =
        'اختار 3 لاعبين مباراة ليفربول × برايتون مضاعفة، '
        'فحصلوا على نقاط المضاعفة، كل لاعب 6 نقاط';
    // The site's link, never an invitation code (removed 2026-10-26).
    const String link = '\nشاركنا في نُخبة: https://nukhbaa.app';
    expect(doubleHitsShareText(doubles, showNames: false), '$sentence$link');
    expect(
      doubleHitsShareText(doubles, showNames: true),
      '$sentence\n1. Ali 6\n2. Huda 6\n3. Omar 6$link',
    );
  });

  testWidgets('a player sees no doubles line', (tester) async {
    await _pump(tester, _Server(role: 'user'));

    expect(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-ali')),
      findsOneWidget,
    );
    expect(find.byKey(_banner), findsNothing);
  });
}
