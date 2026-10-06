/// A reaction shows at once, through the real board, the real reaction
/// sheet, the real `PredictionApi` and a fake server that answers only when
/// told: choosing a reaction closes the sheet and marks the board before the
/// server answers, and a refused save is taken back off the board and said
/// under it.
library;

import 'dart:async';

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
      homeGoals: 2,
      awayGoals: 0,
      isDouble: false,
      displayName: name,
    ).toJson();

/// A started match with the viewer's prediction and sara's, which has no
/// reactions. A reaction is answered once [answer] completes, refused when
/// [refuse] is set.
final class _Server {
  _Server({required this.kickoffAt, this.refuse = false});

  final String kickoffAt;
  final bool refuse;
  final Completer<void> answer = Completer<void>();
  int puts = 0;

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    if (path == _reactPath && request.method == 'PUT') {
      puts++;
      await answer.future;
      return refuse
          ? http.Response('{"error":"unavailable"}', 503)
          : okJsonObject(const {'reacted': true, 'first': true});
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

Future<_Server> _pump(WidgetTester tester, {bool refuse = false}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final String kickoffAt = _minutesAgo(10);
  final _Server server = _Server(kickoffAt: kickoffAt, refuse: refuse);
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

Future<void> _reactWithFire(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')));
  await _frames(tester);
  await tester.tap(find.byKey(const Key('reactionSheet.kind.fire')));
  await _frames(tester);
}

final Finder _saraReactions = find.byKey(
  const Key('fixturePredictions.reactions.f-1.p-sara'),
);

void main() {
  testWidgets('the sheet closes and the board shows it before the server', (
    tester,
  ) async {
    final _Server server = await _pump(tester);

    await _reactWithFire(tester);

    expect(server.puts, 1);
    expect(server.answer.isCompleted, isFalse);
    expect(find.byKey(const Key('reactionSheet')), findsNothing);
    expect(
      find.descendant(of: _saraReactions, matching: find.text('1')),
      findsOneWidget,
    );

    server.answer.complete();
    await _frames(tester);
    expect(_saraReactions, findsOneWidget);
    expect(find.byKey(const Key('reactionSheet.error')), findsNothing);
  });

  testWidgets('a refused reaction is taken back and said', (tester) async {
    final _Server server = await _pump(tester, refuse: true);

    await _reactWithFire(tester);
    expect(_saraReactions, findsOneWidget);

    server.answer.complete();
    await _frames(tester);
    expect(_saraReactions, findsNothing);
    expect(
      find.byKey(const Key('fixturePredictions.reactable.f-1.p-sara')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reactionSheet.error')), findsOneWidget);
  });
}
