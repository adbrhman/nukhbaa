/// The open card's last row through the real matches screen, the real card
/// and a fake server (script 128): the double and the share sit side by
/// side under everyone's calls, and when another match of the same Riyadh
/// day already holds the player's double, this card's toggle says so and a
/// tap sends nothing -- the server would refuse a second double that day.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

/// Two kickoffs a year ahead on the same Riyadh day: 12:00 and 15:00 UTC
/// are 15:00 and 18:00 in Riyadh.
String _kickoff(int hourUtc) {
  final DateTime day = DateTime.now().toUtc().add(const Duration(days: 365));
  return DateTime.utc(day.year, day.month, day.day, hourUtc).toIso8601String();
}

Map<String, Object?> _item(String id, String home, String away, int hour) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'League',
      seasonLabel: '10/2026',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: id,
        homeTeam: home,
        awayTeam: away,
        kickoffAt: _kickoff(hour),
      ),
      homeOutcomeShare: 60,
      drawOutcomeShare: 22,
      awayOutcomeShare: 18,
      totalPredictions: 100,
    ).toJson();

Map<String, Object?> _call(String id, {required bool isDouble}) =>
    FixturePredictionDto(
      id: 'pr-$id',
      participantId: 'p-me',
      fixtureId: id,
      submittedAt: '2026-10-18T10:00:00.000Z',
      homeGoals: 2,
      awayGoals: 1,
      isDouble: isDouble,
      seasonId: 's-1',
    ).toJson();

Future<CurrentMonthFixturesHarness> _pump(
  WidgetTester tester, {
  required List<Map<String, Object?>> feed,
  required List<Map<String, Object?>> calls,
}) async {
  // Tall enough that both cards of the day are built.
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildCurrentMonthFixturesHarness((request) async {
    switch (request.url.path) {
      case '/feed/current-month-fixtures':
        return okJsonList(feed);
      case '/me/fixture-predictions':
        return okJsonList(calls);
      case '/teams':
        return okJsonList(const []);
    }
    return http.Response('not found', 404);
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
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  return harness;
}

Finder _in(Finder of, Finder matching) =>
    find.descendant(of: of, matching: matching);

void main() {
  testWidgets('the double and the share share one row under the shares', (
    tester,
  ) async {
    await _pump(
      tester,
      feed: <Map<String, Object?>>[_item('f-1', 'Arsenal', 'Chelsea', 12)],
      calls: <Map<String, Object?>>[_call('f-1', isDouble: false)],
    );

    final Finder toggle = find.byKey(
      const Key('currentMonthFixtures.double.f-1'),
    );
    final Finder share = find.byKey(
      const Key('currentMonthFixtures.sharePrediction.f-1'),
    );
    final Finder shares = find.byKey(
      const Key('currentMonthFixtures.outcomeShares.f-1'),
    );
    expect(toggle, findsOneWidget);
    expect(share, findsOneWidget);
    expect(
      (tester.getCenter(toggle).dy - tester.getCenter(share).dy).abs(),
      lessThan(1),
    );
    expect(
      tester.getTopLeft(toggle).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(shares).dy),
    );
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the day\'s double on another match: the toggle says so and '
      'a tap sends nothing', (tester) async {
    final harness = await _pump(
      tester,
      feed: <Map<String, Object?>>[
        _item('f-1', 'Arsenal', 'Chelsea', 12),
        _item('f-2', 'Liverpool', 'Everton', 15),
      ],
      calls: <Map<String, Object?>>[_call('f-1', isDouble: true)],
    );

    final Finder taken = find.byKey(
      const Key('currentMonthFixtures.double.f-2'),
    );
    expect(taken, findsOneWidget);
    expect(_in(taken, find.text('مضاعفة اليوم مستخدمة')), findsOneWidget);
    // The match that holds it still offers it, lit.
    final Finder holder = find.byKey(
      const Key('currentMonthFixtures.double.f-1'),
    );
    expect(_in(holder, find.text('مضاعفة اليوم مستخدمة')), findsNothing);
    expect(_in(holder, find.byIcon(Icons.bolt_rounded)), findsOneWidget);

    await tester.tap(taken, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    expect(harness.captured.where((c) => c.request.method != 'GET'), isEmpty);
    expect(_in(taken, find.text('مضاعفة اليوم مستخدمة')), findsOneWidget);
  });
}
