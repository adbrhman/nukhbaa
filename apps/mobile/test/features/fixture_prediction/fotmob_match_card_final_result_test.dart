/// A finished match through the real matches screen, the real card and a
/// fake server: once its result is recorded the card shows the final score
/// as over, whether or not the player predicted it, and a graded card
/// shows the final score above the player's own call and points.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

final String _kickoff = DateTime.now()
    .toUtc()
    .subtract(const Duration(hours: 3))
    .toIso8601String();

Map<String, Object?> _item() => CurrentMonthFixtureItemDto(
  competitionId: 'c-1',
  competitionName: 'League',
  seasonLabel: '10/2026',
  fixture: SeasonFixtureCardDto(
    seasonId: 's-1',
    fixtureId: 'f-1',
    homeTeam: 'Arsenal',
    awayTeam: 'Chelsea',
    kickoffAt: _kickoff,
  ),
  resultHomeGoals: 2,
  resultAwayGoals: 1,
).toJson();

Future<void> _pump(WidgetTester tester, {required bool predicted}) async {
  final harness = buildCurrentMonthFixturesHarness((request) async {
    switch (request.url.path) {
      case '/feed/current-month-fixtures':
        return okJsonList([_item()]);
      case '/me/fixture-predictions':
        return okJsonList([
          if (predicted)
            const FixturePredictionDto(
              id: 'pr-1',
              participantId: 'p-me',
              fixtureId: 'f-1',
              submittedAt: '2026-10-06T10:00:00.000Z',
              homeGoals: 2,
              awayGoals: 0,
              isDouble: false,
              seasonId: 's-1',
            ).toJson(),
        ]);
      case '/seasons/s-1/fixtures/f-1/scores':
        return okJsonObject(
          const FixtureScoresDto(
            fixtureId: 'f-1',
            resultHomeGoals: 2,
            resultAwayGoals: 1,
            scores: <ParticipantFixtureScoreDto>[
              ParticipantFixtureScoreDto(
                fixtureId: 'f-1',
                participantId: 'p-me',
                rulesetVersion: 3,
                grade: 'incorrect',
                points: 0,
              ),
            ],
          ).toJson(),
        );
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
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('an unpredicted finished match shows its final score, over', (
    tester,
  ) async {
    await _pump(tester, predicted: false);

    const Key score = Key('currentMonthFixtures.liveScore.f-1');
    expect(find.byKey(score), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(score), matching: find.text('1 - 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('currentMonthFixtures.liveStatus.f-1')),
        matching: find.text('انتهت'),
      ),
      findsOneWidget,
    );
    expect(find.text('بانتظار النتيجة'), findsNothing);
  });

  testWidgets('a graded card shows the final score above the call', (
    tester,
  ) async {
    await _pump(tester, predicted: true);

    expect(
      find.descendant(
        of: find.byKey(const Key('currentMonthFixtures.liveScore.f-1')),
        matching: find.text('1 - 2'),
      ),
      findsOneWidget,
    );
    // The call (2-0 home) sits in the strip below, with its points.
    final Finder call = find.byKey(
      const Key('currentMonthFixtures.myCall.f-1'),
    );
    expect(
      find.descendant(of: call, matching: find.text('0 - 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('currentMonthFixtures.liveStatus.f-1')),
        matching: find.text('انتهت'),
      ),
      findsOneWidget,
    );
  });
}
