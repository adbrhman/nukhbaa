/// How a player finds out the predictions board can be reacted to, through
/// the real board, the real `PredictionApi` and a fake server: another
/// player's prediction with no reactions yet carries a faint reaction icon
/// (the viewer's own and a reacted one do not), and a line above the table
/// says so until the viewer's first reaction of the day, read from the
/// server's own tallies.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const String _reactPath =
    '/seasons/s-1/fixtures/f-1/predictions/p-sara/reaction';

String _minutesAgo(int minutes) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutes))
    .toIso8601String();

Map<String, Object?> _prediction(String participantId, String name) =>
    FixturePredictionDto(
      id: 'pr-$participantId',
      participantId: participantId,
      fixtureId: 'f-1',
      submittedAt: '2026-10-06T12:00:00.000Z',
      homeGoals: 1,
      awayGoals: 1,
      isDouble: false,
      displayName: name,
    ).toJson();

/// A started match with three predictions: the viewer's, khaled's (one
/// clap from someone else) and sara's (nothing, until the viewer reacts:
/// [mine]).
final class _Server {
  _Server({required this.kickoffAt, this.mine});

  final String kickoffAt;
  String? mine;

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == _reactPath && request.method == 'PUT') {
      mine =
          (jsonDecode(request.body) as Map<String, Object?>)['emoji']
              as String?;
      return okJsonObject(const {'reacted': true, 'first': true});
    }
    switch (path) {
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
              kickoffAt: kickoffAt,
            ),
          ).toJson(),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([_prediction('p-me', 'Ahmad')]);
      case '/seasons/s-1/fixtures/f-1/predictions':
        return okJsonList([
          _prediction('p-me', 'Ahmad'),
          _prediction('p-khaled', 'Khaled'),
          _prediction('p-sara', 'Sara'),
        ]);
      case '/seasons/s-1/fixtures/f-1/scores':
        return okJsonObject(
          const FixtureScoresDto(
            fixtureId: 'f-1',
            scores: <ParticipantFixtureScoreDto>[],
          ).toJson(),
        );
      case '/seasons/s-1/fixtures/f-1/reactions':
        return okJsonObject(
          PredictionReactionsDto(
            reactions: <PredictionReactionTallyDto>[
              const PredictionReactionTallyDto(
                participantId: 'p-khaled',
                counts: <String, int>{'clap': 1},
              ),
              if (mine != null)
                PredictionReactionTallyDto(
                  participantId: 'p-sara',
                  counts: <String, int>{mine!: 1},
                  mine: mine,
                ),
            ],
          ).toJson(),
        );
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Future<_Server> _pump(WidgetTester tester, {String? mine}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final String kickoffAt = _minutesAgo(10);
  final _Server server = _Server(kickoffAt: kickoffAt, mine: mine);
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
        home: FixturePredictionsBoardPage(kickoffAt: kickoffAt),
      ),
    ),
  );
  await _frames(tester);
  return server;
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

const Key _hint = Key('fixturePredictions.reactHint');

Finder _reactable(String participantId) =>
    find.byKey(Key('fixturePredictions.reactable.f-1.$participantId'));

void main() {
  testWidgets('only another player prediction with no reactions invites one', (
    tester,
  ) async {
    await _pump(tester);

    expect(_reactable('p-sara'), findsOneWidget);
    expect(_reactable('p-me'), findsNothing);
    expect(_reactable('p-khaled'), findsNothing);
    expect(
      find.byKey(const Key('fixturePredictions.reactions.f-1.p-khaled')),
      findsOneWidget,
    );
  });

  testWidgets('the line shows until the viewer reacts', (tester) async {
    final _Server server = await _pump(tester);
    expect(find.byKey(_hint), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
    );
    await _frames(tester);
    await tester.tap(find.byKey(const Key('reactionSheet.kind.fire')));
    await _frames(tester);

    expect(server.mine, 'fire');
    expect(find.byKey(_hint), findsNothing);
    expect(_reactable('p-sara'), findsNothing);
    expect(
      find.byKey(const Key('fixturePredictions.reactions.f-1.p-sara')),
      findsOneWidget,
    );
  });

  testWidgets('no line once the viewer has reacted that day', (tester) async {
    await _pump(tester, mine: 'clap');

    expect(find.byKey(_hint), findsNothing);
  });
}
