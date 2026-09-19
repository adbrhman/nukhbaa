/// A locked card shows the provider's running score and minute instead of
/// the bare "live" label, and the final score (still awaiting the official
/// result) once the provider reports the match over.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_registry.dart';
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

Future<void> _pump(
  WidgetTester tester,
  Map<String, Object?> item, {
  Locale locale = const Locale('ar'),
}) async {
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
        // The app ships in Arabic, so that is the default; a test can ask
        // for another locale to check the LTR layout too.
        locale: locale,
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

/// Horizontal centre of the card's name for the team [englishName].
double _teamX(WidgetTester tester, String englishName) =>
    tester.getCenter(find.text(teamDisplayName(englishName)).first).dx;

void main() {
  testWidgets('Arabic: a 2-0 home lead puts the 2 on the home team side', (
    tester,
  ) async {
    await _pump(tester, _item(home: 2, away: 0, minute: 30));

    expect(
      _teamX(tester, 'Arsenal'),
      greaterThan(_teamX(tester, 'Chelsea')),
      reason: 'RTL card: the home team is drawn on the right',
    );
    // The label reads left-to-right, so the home score comes last.
    expect(find.text('0 - 2'), findsOneWidget);
    expect(find.text('2 - 0'), findsNothing);
  });

  testWidgets('English: a 2-0 home lead puts the 2 on the home team side', (
    tester,
  ) async {
    await _pump(
      tester,
      _item(home: 2, away: 0, minute: 30),
      locale: const Locale('en'),
    );

    expect(
      _teamX(tester, 'Arsenal'),
      lessThan(_teamX(tester, 'Chelsea')),
      reason: 'LTR card: the home team is drawn on the left',
    );
    expect(find.text('2 - 0'), findsOneWidget);
    expect(find.text('0 - 2'), findsNothing);
  });

  testWidgets('a running score replaces the live label', (tester) async {
    await _pump(tester, _item(home: 2, away: 1, minute: 67));

    expect(find.byKey(_scoreKey), findsOneWidget);
    // RTL: the home team (2) is drawn on the right, so its score is the
    // last number of the left-to-right label.
    expect(find.text('1 - 2'), findsOneWidget);
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
    expect(find.text('0 - 3'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_scoreKey),
        matching: find.text('بانتظار النتيجة'),
      ),
      findsOneWidget,
    );
  });
}
