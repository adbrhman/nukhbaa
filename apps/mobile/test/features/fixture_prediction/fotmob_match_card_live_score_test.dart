/// A locked card shows the provider's running score and minute instead of
/// the bare "live" label, and the final score (still awaiting the official
/// result) once the provider reports the match over.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Map<String, Object?> _item({
  required int? home,
  required int? away,
  int? minute,
  bool? finished,
}) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'الدوري الإنجليزي',
  seasonLabel: '09/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 2))
        .toIso8601String(),
  ),
  liveHomeGoals: home,
  liveAwayGoals: away,
  liveMinute: minute,
  liveFinished: finished,
).toJson();

Future<void> _pump(WidgetTester tester, Map<String, Object?> item) async {
  final harness = buildCurrentMonthFixturesHarness((request) async {
    final path = request.url.path;
    if (path == '/feed/current-month-fixtures') {
      return okJsonList([item]);
    }
    if (path == '/seasons/s-1/fixtures/f-1/prediction-distribution') {
      return okJsonObject(const {
        'schema_version': 1,
        'home_win_percentage': 50,
        'away_win_percentage': 50,
      });
    }
    if (path == '/seasons/s-1/fixtures/f-1/scores') {
      return okJsonObject(const {
        'schema_version': 1,
        'fixture_id': 'f-1',
        'scores': <Object?>[],
      });
    }
    if (path == '/me/fixture-predictions' || path == '/teams') {
      return okJsonList(const []);
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
        // The app ships in Arabic; assert the Arabic labels.
        locale: const Locale('ar'),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  // The live chip pulses forever, so the tree never settles:
  // pump a bounded number of frames instead.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

const Key _scoreKey = Key('currentMonthFixtures.liveScore.f-1');

void main() {
  testWidgets('a running score replaces the live label', (tester) async {
    await _pump(tester, _item(home: 2, away: 1, minute: 67));

    expect(find.byKey(_scoreKey), findsOneWidget);
    expect(find.text('2 - 1'), findsOneWidget);
    expect(find.text("67'"), findsOneWidget);
  });

  testWidgets('without a running score there is no score', (tester) async {
    await _pump(tester, _item(home: null, away: null));

    expect(find.byKey(_scoreKey), findsNothing);
  });

  testWidgets('a finished match shows its score awaiting the result', (
    tester,
  ) async {
    await _pump(tester, _item(home: 3, away: 0, finished: true));

    expect(find.byKey(_scoreKey), findsOneWidget);
    expect(find.text('3 - 0'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_scoreKey),
        matching: find.text('بانتظار النتيجة'),
      ),
      findsOneWidget,
    );
  });
}
