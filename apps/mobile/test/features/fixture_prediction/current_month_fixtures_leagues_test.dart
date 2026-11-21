/// The matches tab files the day's matches under one header per league
/// (script 301): with several leagues, every header is closed and a tap
/// opens its own; with one league, it is open. The header counts the
/// player's predictions.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

CurrentMonthFixtureItemDto _item(String id, String league, String kickoff) =>
    CurrentMonthFixtureItemDto(
      competitionId: 'c-1',
      competitionName: 'month',
      seasonLabel: '2026/27',
      fixture: SeasonFixtureCardDto(
        seasonId: 's-1',
        fixtureId: id,
        homeTeam: 'Home $id',
        awayTeam: 'Away $id',
        kickoffAt: kickoff,
        leagueName: league,
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  List<CurrentMonthFixtureItemDto> items, {
  List<String> predicted = const <String>[],
}) async {
  final harness = buildCurrentMonthFixturesHarness((
    http.Request request,
  ) async {
    final String path = request.url.path;
    if (path == '/feed/current-month-fixtures') {
      return okJsonList(<Object?>[for (final i in items) i.toJson()]);
    }
    if (path.endsWith('/prediction-distribution')) {
      return okJsonObject(const <String, Object?>{
        'schema_version': 1,
        'home_win_percentage': 50,
        'away_win_percentage': 50,
      });
    }
    if (path == '/me/fixture-predictions') {
      return okJsonList(<Object?>[
        for (final String id in predicted)
          FixturePredictionDto(
            id: 'p-$id',
            participantId: 'part-1',
            fixtureId: id,
            submittedAt: '2026-11-21T09:00:00Z',
            homeGoals: 1,
            awayGoals: 0,
          ).toJson(),
      ]);
    }
    if (path == '/teams') return okJsonList(const <Object?>[]);
    throw StateError('Unexpected request: ${request.method} $path');
  });
  addTearDown(harness.dispose);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // NK301_04
  testWidgets('several leagues: closed headers, a tap opens one', (
    tester,
  ) async {
    final String at = futureIso();
    await _pump(
      tester,
      <CurrentMonthFixtureItemDto>[
        _item('f-1', 'Premier League', at),
        _item('f-2', 'Serie A', at),
        _item('f-3', 'Premier League', at),
      ],
      predicted: <String>['f-3'],
    );

    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Serie A'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('f-1')), findsNothing);
    expect(find.byKey(const ValueKey<String>('f-2')), findsNothing);
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('currentMonthFixtures.league.0.count')),
          )
          .data,
      '1/2',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('currentMonthFixtures.league.1.count')),
          )
          .data,
      '1',
    );

    await tester.tap(find.byKey(const Key('currentMonthFixtures.league.1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('f-2')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('f-1')), findsNothing);

    await tester.tap(find.byKey(const Key('currentMonthFixtures.league.1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('f-2')), findsNothing);
  });

  testWidgets('one league is open', (tester) async {
    final String at = futureIso();
    await _pump(tester, <CurrentMonthFixtureItemDto>[
      _item('f-1', 'Premier League', at),
      _item('f-2', 'Premier League', at),
    ]);

    expect(find.byKey(const Key('currentMonthFixtures.league.0')), findsOne);
    expect(find.byKey(const ValueKey<String>('f-1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('f-2')), findsOneWidget);
  });
}
