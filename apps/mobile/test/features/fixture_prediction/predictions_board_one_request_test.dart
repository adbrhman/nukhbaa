/// The players' predictions board asks for the whole day in ONE request
/// (2026-10-11), through the real page, its real provider and the real
/// `PredictionApi`: the started matches only, none of the three
/// per-match routes from the page itself, and a match that failed for a
/// passing reason comes back when its red mark is tapped.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/time/riyadh_day_turnover.dart';
import 'package:mobile/features/fixture_prediction/predictions_board_providers.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../support/current_month_fixtures_harness.dart';

/// [minutes] before now, kept inside one Riyadh day (as in
/// fixture_predictions_reveal_test.dart): during the first ten minutes of
/// a day, before ten minutes to midnight instead.
String _minutesAgo(int minutes) {
  final DateTime now = DateTime.now().toUtc();
  final DateTime midnight = RiyadhDayTurnover.opensAt(
    RiyadhDayTurnover.dayKeyOf(now),
  );
  final DateTime reference =
      now.difference(midnight) < const Duration(minutes: 15)
      ? midnight.subtract(const Duration(minutes: 15))
      : now;
  return reference.subtract(Duration(minutes: minutes)).toIso8601String();
}

Map<String, Object?> _item(String fixtureId, String kickoffAt) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: fixtureId,
        homeTeam: 'Home $fixtureId',
        awayTeam: 'Away $fixtureId',
        kickoffAt: kickoffAt,
      ),
    ).toJson();

Map<String, Object?> _prediction(String fixtureId, String participantId) =>
    FixturePredictionDto(
      id: 'pr-$fixtureId-$participantId',
      participantId: participantId,
      fixtureId: fixtureId,
      submittedAt: '2026-10-10T12:00:00.000Z',
      homeGoals: 1,
      awayGoals: 0,
      displayName: participantId,
    ).toJson();

/// f-1 and f-2 kicked off; f-3 has not. f-2's predictions time out the
/// first time they are asked for.
final class _Server {
  _Server({required this.firstKickoff, required this.secondKickoff});

  final String firstKickoff;
  final String secondKickoff;
  int f2Asked = 0;

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    switch (path) {
      case '/feed/current-month-fixtures':
        return okJsonList([
          _item('f-1', firstKickoff),
          _item('f-2', secondKickoff),
          _item(
            'f-3',
            DateTime.now()
                .toUtc()
                .add(const Duration(days: 400))
                .toIso8601String(),
          ),
        ]);
      case '/me/fixture-predictions':
        return okJsonList([_prediction('f-1', 'p-me')]);
      case '/seasons/s-1/fixtures/f-1/predictions':
        return okJsonList([
          _prediction('f-1', 'p-me'),
          _prediction('f-1', 'p-sara'),
        ]);
      case '/seasons/s-1/fixtures/f-2/predictions':
        f2Asked++;
        if (f2Asked == 1) {
          return http.Response(
            jsonEncode(const {
              'schema_version': 1,
              'code': 'db.query_timeout',
              'message': 'slow',
            }),
            503,
            headers: const {'content-type': 'application/json'},
          );
        }
        return okJsonList([_prediction('f-2', 'p-sara')]);
      case '/teams':
        return okJsonList(const []);
    }
    if (path.endsWith('/scores')) {
      final String fixtureId = path.split('/')[4];
      return okJsonObject(
        FixtureScoresDto(
          fixtureId: fixtureId,
          scores: const <ParticipantFixtureScoreDto>[],
        ).toJson(),
      );
    }
    if (path.endsWith('/reactions')) {
      return okJsonObject(const {'schema_version': 1, 'reactions': []});
    }
    return http.Response('not found', 404);
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  test('only a passing failure is asked again, three times at most', () {
    const AppError slow = AppError.transient('db.query_timeout', 'slow');
    const AppError refused = AppError.invariant(
      'prediction.fixture_not_started',
      'not yet',
    );

    expect(predictionsBoardRetry(0, slow), const Duration(seconds: 2));
    expect(predictionsBoardRetry(2, slow), const Duration(seconds: 6));
    expect(predictionsBoardRetry(3, slow), isNull);
    expect(predictionsBoardRetry(0, refused), isNull);
    expect(predictionsBoardRetry(0, StateError('x')), isNull);
  });

  test('why a column is empty, in Arabic', () {
    expect(
      predictionsBoardErrorText(null, 'prediction.fixture_not_started'),
      'لم تبدأ المباراة بعد.',
    );
    expect(
      predictionsBoardErrorText(
        const AppError.authorization('prediction.not_a_participant', 'no'),
        null,
      ),
      'لست مشاركاً في هذا الشهر.',
    );
    expect(
      predictionsBoardErrorText(null, 'db.query_timeout'),
      'تعذّر تحميل التوقعات. اضغط لإعادة المحاولة.',
    );
  });

  test('one read per season, at most 40 fixtures each', () {
    SeasonFixtureCardDto card(String seasonId, String fixtureId) =>
        SeasonFixtureCardDto(
          seasonId: seasonId,
          fixtureId: fixtureId,
          homeTeam: 'H',
          awayTeam: 'A',
          kickoffAt: null,
        );
    final Map<String, PredictionsBoardKey> keys = predictionsBoardKeys([
      for (var i = 0; i < 41; i++) card('s-1', 'f-$i'),
      card('s-2', 'g-1'),
      card('s-1', 'f-0'),
    ]);

    expect(keys, hasLength(42));
    expect(keys['s-1/f-0']!.fixtureIds.split(','), hasLength(40));
    expect(keys['s-1/f-39'], keys['s-1/f-0']);
    expect(keys['s-1/f-40'], (seasonId: 's-1', fixtureIds: 'f-40'));
    expect(keys['s-2/g-1'], (seasonId: 's-2', fixtureIds: 'g-1'));
  });

  testWidgets('one request for the day; a failed match comes back on tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final String kickoffAt = _minutesAgo(10);
    final _Server server = _Server(
      firstKickoff: _minutesAgo(12),
      secondKickoff: kickoffAt,
    );
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

    // What the page itself sent: one board read, nothing per match.
    List<http.Request> sent(bool Function(String path) test) => [
      for (final CapturedRequest c in harness.captured)
        if (test(c.request.url.path)) c.request,
    ];
    final List<http.Request> boards = sent(
      (p) => p == '/seasons/s-1/predictions-board',
    );
    expect(boards, hasLength(1));
    expect(boards.single.url.queryParameters['fixtures'], 'f-1,f-2');
    expect(sent((p) => p.startsWith('/seasons/s-1/fixtures/')), isEmpty);

    expect(
      find.byKey(const Key('fixturePredictions.header.f-3')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('fixturePredictions.retry.f-2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('fixturePredictions.cell.f-2.p-sara')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('fixturePredictions.retry.f-2')));
    await _frames(tester);

    expect(sent((p) => p == '/seasons/s-1/predictions-board'), hasLength(2));
    expect(find.byKey(const Key('fixturePredictions.retry.f-2')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('fixturePredictions.cell.f-2.p-sara')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });
}
