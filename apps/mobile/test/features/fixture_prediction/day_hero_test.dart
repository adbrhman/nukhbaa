/// The hero of the day through the real predictions board, the real reaction
/// sheet, the real `GET /me` and a fake server: the one player who alone
/// called a finished match exactly is named above the table for an admin
/// and marked in the cell, and tapping that prediction opens the card to
/// share. A player is not shown any of it, and a match two players called
/// exactly has no hero.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

String _hoursAgo(int hours) =>
    DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String();

Map<String, Object?> _prediction(String participantId, String name, int h) =>
    FixturePredictionDto(
      id: 'pr-$participantId',
      participantId: participantId,
      fixtureId: 'f-1',
      submittedAt: '2026-10-07T12:00:00.000Z',
      homeGoals: h,
      awayGoals: 0,
      isDouble: false,
      displayName: name,
    ).toJson();

ParticipantFixtureScoreDto _score(String participantId, String grade) =>
    ParticipantFixtureScoreDto(
      fixtureId: 'f-1',
      participantId: participantId,
      rulesetVersion: 3,
      grade: grade,
      points: grade == 'exact_scoreline' ? 3 : 0,
    );

/// A finished match, Slovakia 4-0 Moldova. Sara called 4-0; Ahmad (the
/// viewer) called 1-0, unless [twoExact], when he called 4-0 too.
final class _Server {
  _Server({required this.role, this.twoExact = false});

  final String role;
  final bool twoExact;
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
              displayName: 'Ahmad',
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
              homeTeam: 'Slovakia',
              awayTeam: 'Moldova',
              kickoffAt: kickoffAt,
            ),
          ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([_prediction('p-me', 'Ahmad', twoExact ? 4 : 1)]);
      case '/seasons/s-1/fixtures/f-1/predictions':
        return okJsonList([
          _prediction('p-me', 'Ahmad', twoExact ? 4 : 1),
          _prediction('p-sara', 'Sara', 4),
        ]);
      case '/seasons/s-1/fixtures/f-1/scores':
        return okJsonObject(
          FixtureScoresDto(
            fixtureId: 'f-1',
            scores: <ParticipantFixtureScoreDto>[
              _score('p-me', twoExact ? 'exact_scoreline' : 'incorrect'),
              _score('p-sara', 'exact_scoreline'),
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

const Key _banner = Key('fixturePredictions.hero.f-1');
const Key _mark = Key('fixturePredictions.heroMark.f-1.p-sara');
const Key _share = Key('reactionSheet.shareHero');

void main() {
  testWidgets('an admin sees the hero and opens the card from the call', (
    tester,
  ) async {
    await _pump(tester, _Server(role: 'admin'));

    expect(find.byKey(_banner), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_banner),
        matching: find.textContaining('Sara'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(_mark), findsOneWidget);
    expect(
      find.byKey(const Key('fixturePredictions.heroMark.f-1.p-me')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
    );
    await _frames(tester);
    expect(find.byKey(_share), findsOneWidget);

    await tester.tap(find.byKey(_share));
    await _frames(tester);
    final Finder card = find.byKey(const Key('dayHero.card'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('بطاقة بطل النخبة لليوم')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('dayHero.name'))).data,
      'Sara',
    );
    expect(find.byKey(const Key('dayHero.solo')), findsOneWidget);
    final Finder score = find.byKey(const Key('dayHero.score'));
    expect(
      find.descendant(of: score, matching: find.text('4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: score, matching: find.text('0')),
      findsOneWidget,
    );
  });

  testWidgets('the banner opens the same card', (tester) async {
    await _pump(tester, _Server(role: 'admin'));

    await tester.tap(find.byKey(_banner));
    await _frames(tester);

    expect(find.byKey(const Key('dayHero.card')), findsOneWidget);
  });

  testWidgets('a player sees no hero and no card', (tester) async {
    await _pump(tester, _Server(role: 'user'));

    expect(find.byKey(_banner), findsNothing);
    expect(find.byKey(_mark), findsNothing);
    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
    );
    await _frames(tester);
    expect(find.byKey(const Key('reactionSheet')), findsOneWidget);
    expect(find.byKey(_share), findsNothing);
  });

  testWidgets('two exact calls make no hero', (tester) async {
    await _pump(tester, _Server(role: 'admin', twoExact: true));

    expect(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
      findsOneWidget,
    );
    expect(find.byKey(_banner), findsNothing);
    expect(find.byKey(_mark), findsNothing);
  });
}
