/// "Everyone's predictions" on the match card: offered only once the match
/// has kicked off, in the slot the double button held before kickoff, and
/// fed by the server's reveal (`GET .../fixtures/{id}/predictions`).
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

const Key _revealKey = Key('currentMonthFixtures.reveal.f-1');

Map<String, Object?> _item(String kickoffIso) => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'الدوري الإنجليزي',
  seasonLabel: '09/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: kickoffIso,
  ),
).toJson();

Map<String, Object?> _prediction({
  required String participantId,
  required String name,
  required int home,
  required int away,
  bool isDouble = false,
}) => FixturePredictionDto(
  id: 'pr-$participantId',
  participantId: participantId,
  fixtureId: 'f-1',
  submittedAt: '2026-09-28T12:00:00.000Z',
  homeGoals: home,
  awayGoals: away,
  isDouble: isDouble,
  displayName: name,
).toJson();

Future<List<String>> _pump(WidgetTester tester, String kickoffIso) async {
  final List<String> paths = <String>[];
  final harness = buildCurrentMonthFixturesHarness((request) async {
    final path = request.url.path;
    paths.add(path);
    if (path == '/feed/current-month-fixtures') {
      return okJsonList([_item(kickoffIso)]);
    }
    if (path == '/me/fixture-predictions') {
      return okJsonList([
        _prediction(participantId: 'p-me', name: 'أحمد', home: 2, away: 1),
      ]);
    }
    if (path == '/seasons/s-1/fixtures/f-1/predictions') {
      return okJsonList([
        _prediction(participantId: 'p-me', name: 'أحمد', home: 2, away: 1),
        _prediction(
          participantId: 'p-khaled',
          name: 'خالد',
          home: 0,
          away: 3,
          isDouble: true,
        ),
      ]);
    }
    if (path == '/seasons/s-1/fixtures/f-1/scores') {
      return okJsonObject(const {
        'schema_version': 1,
        'fixture_id': 'f-1',
        'scores': <Object?>[],
      });
    }
    if (path == '/seasons/s-1/fixtures/f-1/prediction-distribution') {
      return okJsonObject(const {
        'schema_version': 1,
        'home_win_percentage': 50,
        'away_win_percentage': 50,
      });
    }
    if (path == '/teams') {
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
        locale: const Locale('ar'),
        home: const CurrentMonthFixturesScreen(),
      ),
    ),
  );
  // A started card's live chip pulses forever: pump bounded frames.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  return paths;
}

void main() {
  testWidgets('before kickoff there is no way to see other predictions', (
    tester,
  ) async {
    final paths = await _pump(tester, futureIso());

    expect(find.byKey(_revealKey), findsNothing);
    expect(
      find.byKey(const Key('currentMonthFixtures.double.f-1')),
      findsOneWidget,
    );
    expect(paths, isNot(contains('/seasons/s-1/fixtures/f-1/predictions')));
  });

  testWidgets('after kickoff the card opens everyone\'s predictions', (
    tester,
  ) async {
    final String startedIso = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 3))
        .toIso8601String();
    final paths = await _pump(tester, startedIso);

    expect(find.byKey(_revealKey), findsOneWidget);
    expect(
      find.byKey(const Key('currentMonthFixtures.double.f-1')),
      findsNothing,
    );
    expect(paths, isNot(contains('/seasons/s-1/fixtures/f-1/predictions')));

    await tester.ensureVisible(find.byKey(_revealKey));
    await tester.tap(find.byKey(_revealKey));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(paths, contains('/seasons/s-1/fixtures/f-1/predictions'));
    expect(find.byKey(const Key('fixturePredictions.list')), findsOneWidget);
    expect(find.text('أحمد (أنت)'), findsOneWidget);
    expect(find.text('خالد'), findsOneWidget);
    expect(
      find.byKey(const Key('fixturePredictions.double.p-khaled')),
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
