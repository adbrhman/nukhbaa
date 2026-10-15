/// The players' predictions board when the day could not be read (batch
/// 156), through the real page, provider and `PredictionApi`: it says so
/// with a retry instead of "no predictions yet" (the server was saturated,
/// the predictions were there), and the retry brings the board.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/time/riyadh_day_turnover.dart';
import 'package:mobile/features/fixture_prediction/widgets/fixture_predictions_board_page.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

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

/// Both started matches time out until [down] is cleared.
final class _Server {
  _Server(this.kickoffAt);

  final String kickoffAt;
  bool down = true;

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    switch (path) {
      case '/feed/current-month-fixtures':
        return okJsonList([_item('f-1', kickoffAt), _item('f-2', kickoffAt)]);
      case '/me/fixture-predictions':
      case '/teams':
        return okJsonList(const []);
    }
    if (path.endsWith('/predictions')) {
      if (down) {
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
      final String fixtureId = path.split('/')[4];
      return okJsonList([
        FixturePredictionDto(
          id: 'pr-$fixtureId',
          participantId: 'p-sara',
          fixtureId: fixtureId,
          submittedAt: '2026-10-10T12:00:00.000Z',
          homeGoals: 1,
          awayGoals: 0,
          displayName: 'Sara',
        ).toJson(),
      ]);
    }
    if (path.endsWith('/scores')) {
      return okJsonObject(
        FixtureScoresDto(
          fixtureId: path.split('/')[4],
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
  testWidgets('a day that could not be read says so, and the retry brings '
      'it', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final String kickoffAt = _minutesAgo(10);
    final _Server server = _Server(kickoffAt);
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

    expect(find.byKey(const Key('fixturePredictions.empty')), findsNothing);
    expect(find.byKey(const Key('fixturePredictions.failed')), findsOneWidget);

    server.down = false;
    await tester.tap(find.byKey(const Key('fixturePredictions.retry')));
    await _frames(tester);

    expect(find.byKey(const Key('fixturePredictions.failed')), findsNothing);
    expect(
      find.byKey(const Key('fixturePredictions.cell.f-1.p-sara')),
      findsOneWidget,
    );
  });
}
