/// The caller's own points come from ONE read, `GET /me/fixture-scores`
/// (script 75): every finished card shares it -- through the real matches
/// screen, its cards, the real provider and `CompetitionApi` over a faked
/// socket -- and no card asks for its own match's scores any more. The
/// read is repeated only when the feed shows a new result, and every
/// 2 minutes while a recorded result still waits for its grade.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/ui/app_badge.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/features/history/my_fixture_scores_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

final String _kickoff = DateTime.now()
    .toUtc()
    .subtract(const Duration(hours: 3))
    .toIso8601String();

Map<String, Object?> _item(String fixtureId, {bool finished = true}) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: fixtureId,
        homeTeam: 'Home $fixtureId',
        awayTeam: 'Away $fixtureId',
        kickoffAt: _kickoff,
      ),
      resultHomeGoals: finished ? 2 : null,
      resultAwayGoals: finished ? 1 : null,
    ).toJson();

Map<String, Object?> _prediction(String fixtureId) => FixturePredictionDto(
  id: 'pr-$fixtureId',
  participantId: 'p-me',
  fixtureId: fixtureId,
  submittedAt: '2026-10-06T10:00:00.000Z',
  homeGoals: 2,
  awayGoals: 1,
  isDouble: false,
  seasonId: 's-1',
).toJson();

Map<String, Object?> _row(String fixtureId, {String? grade, int? points}) =>
    MyFixtureScoreDto(
      participantId: 'p-me',
      fixtureId: fixtureId,
      grade: grade,
      points: points,
      resultHomeGoals: 2,
      resultAwayGoals: 1,
    ).toJson();

/// Counts what the app asked for, by path.
final class _Server {
  _Server({required this.feed, required this.scores});

  List<Map<String, Object?>> feed;
  List<Map<String, Object?>> Function(int read) scores;
  final List<String> paths = <String>[];

  int count(String path) => paths.where((String p) => p == path).length;

  Future<http.Response> handle(http.Request request) async {
    final String path = request.url.path;
    paths.add(path);
    switch (path) {
      case '/feed/current-month-fixtures':
        return okJsonList(feed);
      case '/me/fixture-predictions':
        return okJsonList([_prediction('f-1'), _prediction('f-2')]);
      case '/me/fixture-scores':
        return okJsonList(scores(count(path)));
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
  }
}

Widget _host(CurrentMonthFixturesHarness harness, Widget home) => ProviderScope(
  overrides: harness.overrides,
  retry: (retryCount, error) => null,
  child: MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: const Locale('ar'),
    home: home,
  ),
);

/// A bare reader of the provider: its row count, or "-" until it has one.
Widget _probe() => Scaffold(
  body: Consumer(
    builder: (BuildContext context, WidgetRef ref, _) {
      final Map<MyFixtureScoreKey, MyFixtureScoreDto>? rows = ref
          .watch(myFixtureScoresProvider)
          .value;
      final MyFixtureScoreDto? first = rows == null || rows.isEmpty
          ? null
          : rows.values.first;
      return Text(rows == null ? '-' : '${rows.length} ${first?.grade}');
    },
  ),
);

/// Lets each answer of the faked server reach the screen: the feed, then
/// the read it lets through.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

String _pointsOn(WidgetTester tester, String fixtureId) => tester
    .widget<AppBadge>(
      find.descendant(
        of: find.byKey(Key('currentMonthFixtures.myCall.$fixtureId')),
        matching: find.byType(AppBadge),
      ),
    )
    .label;

void main() {
  testWidgets('two finished cards share one read of my points', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final _Server server = _Server(
      feed: [_item('f-1'), _item('f-2')],
      scores: (_) => [
        _row('f-1', grade: 'exact_scoreline', points: 3),
        _row('f-2', grade: 'incorrect', points: 0),
      ],
    );
    final harness = buildCurrentMonthFixturesHarness(server.handle);
    addTearDown(harness.dispose);

    await tester.pumpWidget(_host(harness, const CurrentMonthFixturesScreen()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(_pointsOn(tester, 'f-1'), '3 نقاط');
    expect(_pointsOn(tester, 'f-2'), '0 نقطة');
    expect(server.count('/me/fixture-scores'), 1);
    expect(
      server.paths.where((String p) => p.endsWith('/scores')),
      isEmpty,
      reason: 'no card asks for its own match any more',
    );
  });

  testWidgets('a result waiting for its grade is read again after 2 minutes, '
      'then no more', (tester) async {
    final _Server server = _Server(
      feed: [_item('f-1')],
      scores: (int read) => [
        if (read < 2)
          _row('f-1')
        else
          _row('f-1', grade: 'exact_scoreline', points: 3),
      ],
    );
    final harness = buildCurrentMonthFixturesHarness(server.handle);
    addTearDown(harness.dispose);

    await tester.pumpWidget(_host(harness, _probe()));
    await _settle(tester);
    expect(server.count('/me/fixture-scores'), 1);
    expect(find.text('1 null'), findsOneWidget);

    await tester.pump(myFixtureScoresRetryDelay);
    await _settle(tester);
    expect(server.count('/me/fixture-scores'), 2);
    expect(find.text('1 exact_scoreline'), findsOneWidget);

    await tester.pump(myFixtureScoresRetryDelay);
    await _settle(tester);
    expect(
      server.count('/me/fixture-scores'),
      2,
      reason: 'graded: nothing left to wait for',
    );
  });

  testWidgets('a new result in the feed reads my points again; '
      'a feed refresh with nothing new does not', (tester) async {
    final _Server server = _Server(
      feed: [_item('f-1', finished: false)],
      scores: (_) => const [],
    );
    final harness = buildCurrentMonthFixturesHarness(server.handle);
    addTearDown(harness.dispose);

    await tester.pumpWidget(_host(harness, _probe()));
    await _settle(tester);
    expect(server.count('/me/fixture-scores'), 1);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
    );

    // The match ends: the feed's next refresh carries its result.
    server.feed = [_item('f-1')];
    server.scores = (_) => [_row('f-1', grade: 'incorrect', points: 0)];
    container.invalidate(currentMonthFixturesProvider);
    await _settle(tester);
    expect(server.count('/me/fixture-scores'), 2);
    expect(find.text('1 incorrect'), findsOneWidget);

    // The minute tick refreshes the feed again; nothing new finished.
    container.invalidate(currentMonthFixturesProvider);
    await _settle(tester);
    expect(server.count('/feed/current-month-fixtures'), 3);
    expect(server.count('/me/fixture-scores'), 2);
  });
}
