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
import 'package:mobile/core/design/app_tokens.dart';
import 'package:mobile/features/competition/team_registry.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/current_month_fixtures_harness.dart';

Widget _host(
  CurrentMonthFixturesHarness harness,
  Widget child, {
  Locale? locale,
}) => ProviderScope(
  overrides: harness.overrides,
  retry: (retryCount, error) => null,
  child: MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    locale: locale,
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
          homeWinPercentage: 68,
          awayWinPercentage: 32,
        ).toJson(),
      ]);
    }
    if (path == '/seasons/s-1/fixtures/f-1/prediction-distribution') {
      return okJsonObject(const {
        'schema_version': 1,
        'home_win_percentage': 68,
        'away_win_percentage': 32,
      });
    }
    if (path == '/seasons/s-1/fixtures/f-1/prediction') {
      return okJsonObject({
        'schema_version': 1,
        'id': 'fp-1',
        'participant_id': 'part-1',
        'fixture_id': 'f-1',
        'submitted_at': '2026-09-12T20:00:00.000Z',
        'home_goals': 0,
        'away_goals': 0,
        'is_double': false,
      });
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

/// Horizontal centre of the card's name for the team [englishName].
double _teamX(WidgetTester tester, String englishName) =>
    tester.getCenter(find.text(teamDisplayName(englishName)).first).dx;

void main() {
  testWidgets(
    'graded state, Arabic: the stored 2-0 forecast puts the 2 on the home side',
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
            awayGoals: 0,
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
        _host(
          harness,
          const CurrentMonthFixturesScreen(),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _teamX(tester, 'Al Hilal'),
        greaterThan(_teamX(tester, 'Al Nassr')),
        reason: 'RTL card: the home team is drawn on the right',
      );
      // The label reads left-to-right, so the home score comes last.
      expect(find.text('0 - 2'), findsOneWidget);
      expect(find.text('2 - 0'), findsNothing);
    },
  );

  testWidgets('open state: score changes auto-save and show a check', (
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
    expect(
      find.byKey(const Key('currentMonthFixtures.submit.f-1')),
      findsNothing,
      reason: 'auto-save replaces the explicit submit control',
    );
    expect(find.text('68%'), findsOneWidget);
    expect(find.text('32%'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('currentMonthFixtures.home.increment.f-1')),
    );
    await tester.tap(
      find.byKey(const Key('currentMonthFixtures.away.increment.f-1')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    final request = harness.captured.firstWhere(
      (c) => c.request.url.path == '/seasons/s-1/fixtures/f-1/prediction',
    );
    expect(request.request.method, 'POST');
    final checkIcon = tester.widget<Icon>(find.byIcon(Icons.check_rounded));
    expect(checkIcon.color, Colors.white);
    final badge = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.check_rounded),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      badge.constraints,
      const BoxConstraints.tightFor(width: 48, height: 48),
    );
    expect((badge.decoration! as BoxDecoration).color, AppTokens.dark.primary);
  });

  testWidgets(
    'predicted state: steppers are pre-filled from the stored prediction',
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
      // No standalone "pending result" badge in this state (removed in the
      // reference-parity pass — it had no counterpart in the reference and
      // added a fourth row).
      expect(find.text('Result pending'), findsNothing);
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

      // Kicked off a day ago: past the live window, not graded yet.
      expect(find.text('Result pending'), findsOneWidget);
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
        find.text('Result pending'),
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
