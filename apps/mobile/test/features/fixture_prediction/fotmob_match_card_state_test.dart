/// Covers `FotmobMatchCard`'s four mutually-exclusive states (§6 of
/// `match-card-fotmob-spec.md`, priority order graded > locked > predicted >
/// open), independent of any live device/emulator — each case pumps the
/// real [CurrentMonthFixturesScreen] against a faked transport and asserts
/// on the card's actual `Key`s/icons/text.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Widget _host(CurrentMonthFixturesHarness harness, Widget child) =>
    ProviderScope(
      overrides: harness.overrides,
      retry: (retryCount, error) => null,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: child,
      ),
    );

CurrentMonthFixturesHarness _harnessFor({
  required String kickoffAt,
  required List<Object?> myPredictions,
  required List<Object?> scores,
}) {
  return buildCurrentMonthFixturesHarness((request) async {
    final path = request.url.path;
    if (path == '/feed/current-month-fixtures') {
      return okJsonList([
        CurrentMonthFixtureItemDto(
          competitionId: 'c-1',
          competitionName: 'الدوري السعودي',
          seasonLabel: '2026/27',
          fixture: SeasonFixtureCardDto(
            seasonId: 's-1',
            fixtureId: 'f-1',
            homeTeam: 'Al Hilal',
            awayTeam: 'Al Nassr',
            kickoffAt: kickoffAt,
          ),
        ).toJson(),
      ]);
    }
    if (path == '/me/fixture-predictions') {
      return okJsonList(myPredictions);
    }
    if (path == '/seasons/s-1/fixtures/f-1/scores') {
      return okJsonObject({
        'schema_version': 1,
        'fixture_id': 'f-1',
        'scores': scores,
      });
    }
    if (path == '/teams') {
      return okJsonList(const []);
    }
    throw StateError('Unexpected request: ${request.method} $path');
  });
}

String _futureIso() =>
    DateTime.now().toUtc().add(const Duration(days: 365)).toIso8601String();
String _pastIso() =>
    DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String();

void main() {
  testWidgets('open state: steppers show "?" and submit stays disabled', (
    tester,
  ) async {
    final harness = _harnessFor(
      kickoffAt: _futureIso(),
      myPredictions: const [],
      scores: const [],
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(_host(harness, const CurrentMonthFixturesScreen()));
    await tester.pumpAndSettle();

    expect(
      find.text('?'),
      findsNWidgets(2),
      reason: 'both steppers must start unset, never a default 0-0',
    );
    final submit = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('currentMonthFixtures.submit.f-1')),
        matching: find.byType(InkWell),
      ),
    );
    expect(
      submit.onTap,
      isNull,
      reason: 'submit must stay disabled until both sides have a pick',
    );
  });

  testWidgets(
    'predicted state: steppers are pre-filled and the pending badge shows',
    (tester) async {
      final harness = _harnessFor(
        kickoffAt: _futureIso(),
        myPredictions: [
          FixturePredictionDto(
            id: 'fp-1',
            participantId: 'part-1',
            fixtureId: 'f-1',
            submittedAt: '2026-09-01T10:00:00.000Z',
            homeGoals: 2,
            awayGoals: 1,
            isDouble: false,
          ).toJson(),
        ],
        scores: const [],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const CurrentMonthFixturesScreen()),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('currentMonthFixtures.home.value.f-1')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('currentMonthFixtures.home.value.f-1')),
            )
            .data,
        '2',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('currentMonthFixtures.away.value.f-1')),
            )
            .data,
        '1',
      );
      expect(find.text('Result pending'), findsOneWidget);
    },
  );

  testWidgets(
    'locked state: shows the lock indicator and hides steppers/submit even with a prediction',
    (tester) async {
      final harness = _harnessFor(
        kickoffAt: _pastIso(),
        myPredictions: [
          FixturePredictionDto(
            id: 'fp-1',
            participantId: 'part-1',
            fixtureId: 'f-1',
            submittedAt: '2026-09-01T10:00:00.000Z',
            homeGoals: 2,
            awayGoals: 1,
            isDouble: false,
          ).toJson(),
        ],
        scores: const [],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const CurrentMonthFixturesScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Started'), findsOneWidget);
      expect(
        find.byKey(const Key('currentMonthFixtures.home.increment.f-1')),
        findsNothing,
        reason: 'a locked fixture must hide the steppers entirely',
      );
      expect(
        find.byKey(const Key('currentMonthFixtures.submit.f-1')),
        findsNothing,
        reason: 'a locked fixture must hide the submit control entirely',
      );
    },
  );

  testWidgets(
    'graded state: shows the stored scoreline + points, wins over everything else',
    (tester) async {
      final harness = _harnessFor(
        kickoffAt: _pastIso(),
        myPredictions: [
          FixturePredictionDto(
            id: 'fp-1',
            participantId: 'part-1',
            fixtureId: 'f-1',
            submittedAt: '2026-09-01T10:00:00.000Z',
            homeGoals: 2,
            awayGoals: 1,
            isDouble: false,
          ).toJson(),
        ],
        scores: [
          ParticipantFixtureScoreDto(
            fixtureId: 'f-1',
            participantId: 'part-1',
            rulesetVersion: 1,
            grade: 'exact_scoreline',
            points: 5,
          ).toJson(),
        ],
      );
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        _host(harness, const CurrentMonthFixturesScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 - 1'), findsOneWidget);
      expect(find.text('5 pts'), findsOneWidget);
      expect(
        find.text('Started'),
        findsNothing,
        reason: 'graded must win over locked in the middle slot',
      );
      expect(
        find.byKey(const Key('currentMonthFixtures.submit.f-1')),
        findsNothing,
      );
    },
  );
}
