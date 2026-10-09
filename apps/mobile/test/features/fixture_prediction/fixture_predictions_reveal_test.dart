/// "All predictions" on a started match card opens the day's table: one row
/// per player, one column per started match of that day, each cell the
/// predicted score with its verdict. Nothing is offered before kickoff.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/time/riyadh_day_turnover.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const Key _revealKey = Key('currentMonthFixtures.reveal.f-1');

Map<String, Object?> _item(String fixtureId, String kickoffIso) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'الدوري الإنجليزي',
      seasonLabel: '09/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: fixtureId,
        homeTeam: 'Arsenal',
        awayTeam: 'Chelsea',
        kickoffAt: kickoffIso,
      ),
    ).toJson();

Map<String, Object?> _prediction(
  String fixtureId, {
  required String participantId,
  required String name,
  required int home,
  required int away,
  bool isDouble = false,
}) => FixturePredictionDto(
  id: 'pr-$fixtureId-$participantId',
  participantId: participantId,
  fixtureId: fixtureId,
  submittedAt: '2026-09-28T12:00:00.000Z',
  homeGoals: home,
  awayGoals: away,
  isDouble: isDouble,
  displayName: name,
).toJson();

Map<String, Object?> _scores(
  String fixtureId,
  List<(String participantId, String grade, int points)> rows,
) => FixtureScoresDto(
  fixtureId: fixtureId,
  scores: <ParticipantFixtureScoreDto>[
    for (final (participantId, grade, points) in rows)
      ParticipantFixtureScoreDto(
        fixtureId: fixtureId,
        participantId: participantId,
        rulesetVersion: 1,
        grade: grade,
        points: points,
      ),
  ],
).toJson();

Future<List<String>> _pump(
  WidgetTester tester,
  List<Map<String, Object?>> items,
) async {
  final List<String> paths = <String>[];
  final harness = buildCurrentMonthFixturesHarness((request) async {
    final path = request.url.path;
    paths.add(path);
    switch (path) {
      case '/feed/current-month-fixtures':
        return okJsonList(items);
      case '/me/fixture-predictions':
        return okJsonList([
          _prediction(
            'f-1',
            participantId: 'p-me',
            name: 'أحمد',
            home: 2,
            away: 1,
          ),
          _prediction(
            'f-2',
            participantId: 'p-me',
            name: 'أحمد',
            home: 0,
            away: 0,
          ),
        ]);
      case '/seasons/s-1/fixtures/f-1/predictions':
        return okJsonList([
          _prediction(
            'f-1',
            participantId: 'p-me',
            name: 'أحمد',
            home: 2,
            away: 1,
          ),
          _prediction(
            'f-1',
            participantId: 'p-khaled',
            name: 'خالد',
            home: 2,
            away: 1,
            isDouble: true,
          ),
        ]);
      case '/seasons/s-1/fixtures/f-2/predictions':
        return okJsonList([
          _prediction(
            'f-2',
            participantId: 'p-me',
            name: 'أحمد',
            home: 0,
            away: 0,
          ),
        ]);
      case '/seasons/s-1/fixtures/f-1/scores':
        return okJsonObject(
          _scores('f-1', [
            ('p-me', 'exact_scoreline', 3),
            ('p-khaled', 'exact_scoreline', 6),
          ]),
        );
      case '/seasons/s-1/fixtures/f-2/scores':
        return okJsonObject(_scores('f-2', [('p-me', 'incorrect', 0)]));
      case '/teams':
        return okJsonList(const []);
    }
    if (path.endsWith('/reactions')) {
      return okJsonObject(const {'schema_version': 1, 'reactions': []});
    }
    if (path.endsWith('/prediction-distribution')) {
      return okJsonObject(const {
        'schema_version': 1,
        'home_win_percentage': 50,
        'away_win_percentage': 50,
      });
    }
    throw StateError('Unexpected request: ${request.method} $path');
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        locale: const Locale('ar'),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  // A started card's live chip pulses forever: pump bounded frames.
  await _frames(tester);
  return paths;
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// [minutes] before a reference that keeps every call in one Riyadh day
/// (the day the tab files a match under): now, or ten minutes before
/// midnight Riyadh during the first ten minutes of a day. The started
/// matches of "the day" must share a day, or the screen opens on a day that
/// holds only some of them: a full run at 00:03 put the two matches on
/// either side of midnight and failed (2026-10-08).
String _minutesAgo(int minutes) {
  final DateTime now = DateTime.now().toUtc();
  final DateTime midnight = RiyadhDayTurnover.opensAt(
    RiyadhDayTurnover.dayKeyOf(now),
  );
  final DateTime reference =
      now.difference(midnight) < const Duration(minutes: 10)
      ? midnight.subtract(const Duration(minutes: 10))
      : now;
  return reference
      .toUtc()
      .subtract(Duration(minutes: minutes))
      .toIso8601String();
}

void main() {
  test('the verdict mark follows the server grade only', () {
    ParticipantFixtureScoreDto score(int points) => ParticipantFixtureScoreDto(
      fixtureId: 'f',
      participantId: 'p',
      rulesetVersion: 1,
      grade: points > 0 ? 'exact_scoreline' : 'incorrect',
      points: points,
    );
    expect(verdictMark(isDouble: false, score: score(3)), '✅');
    expect(verdictMark(isDouble: true, score: score(6)), '⚡🔥');
    expect(verdictMark(isDouble: false, score: score(0)), '❌');
    expect(verdictMark(isDouble: true, score: score(0)), '❌');
    expect(verdictMark(isDouble: false, score: null), '');
    expect(verdictMark(isDouble: true, score: null), '⚡');
  });

  testWidgets('before kickoff there is no way to see other predictions', (
    tester,
  ) async {
    final paths = await _pump(tester, [_item('f-1', futureIso())]);

    expect(find.byKey(_revealKey), findsNothing);
    expect(
      find.byKey(const Key('currentMonthFixtures.double.f-1')),
      findsOneWidget,
    );
    expect(paths.where((p) => p.endsWith('/predictions')), isEmpty);
  });

  testWidgets('the day table lists every player against every started match', (
    tester,
  ) async {
    final paths = await _pump(tester, [
      _item('f-1', _minutesAgo(4)),
      _item('f-2', _minutesAgo(3)),
      _item('f-3', futureIso()),
    ]);

    expect(find.byKey(_revealKey), findsOneWidget);
    expect(paths.where((p) => p.endsWith('/predictions')), isEmpty);

    await tester.ensureVisible(find.byKey(_revealKey));
    await tester.tap(find.byKey(_revealKey));
    await _frames(tester);

    expect(find.byType(FixturePredictionsBoardPage), findsOneWidget);
    // Started matches only: the upcoming one is never asked for.
    expect(paths, contains('/seasons/s-1/fixtures/f-1/predictions'));
    expect(paths, contains('/seasons/s-1/fixtures/f-2/predictions'));
    expect(paths, isNot(contains('/seasons/s-1/fixtures/f-3/predictions')));
    expect(
      find.byKey(const Key('fixturePredictions.header.f-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('fixturePredictions.header.f-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('fixturePredictions.header.f-3')),
      findsNothing,
    );

    expect(find.text('أحمد (أنت)'), findsOneWidget);
    expect(
      find.byKey(const Key('fixturePredictions.row.p-khaled')),
      findsOneWidget,
    );

    Text mark(String fixtureId, String participantId) => tester.widget<Text>(
      find.byKey(Key('fixturePredictions.mark.$fixtureId.$participantId')),
    );
    expect(mark('f-1', 'p-me').data, '✅');
    expect(mark('f-1', 'p-khaled').data, '⚡🔥');
    expect(mark('f-2', 'p-me').data, '❌');
    expect(
      find.descendant(
        of: find.byKey(const Key('fixturePredictions.cell.f-2.p-khaled')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('fixturePredictions.search')),
      'خالد',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('fixturePredictions.row.p-khaled')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('fixturePredictions.row.p-me')), findsNothing);
  });
}
