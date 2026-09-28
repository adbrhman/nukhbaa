/// Widget tests for [PredictionHistoryScreen], wired through the real screen
/// + providers over [buildPredictionHarness] (a `MockClient` transport,
/// already used by the Prediction-submit tests — it overrides
/// `predictionApiProvider`, for `GET /me/fixture-predictions`).
///
/// Round-scoped prediction history (`GET /me/predictions`) was dropped from
/// this screen (docs/project-context.md, "Legacy `Round` predictions in
/// `prediction_history_screen.dart`") — the app has not launched yet, so
/// there was no external history to preserve.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/competition/team_registry.dart';
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/prediction_harness.dart';

Widget _host(PredictionHarness harness, Widget child) => ProviderScope(
  overrides: harness.overrides,
  child: MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  ),
);

void main() {
  group('PredictionHistoryScreen', () {
    testWidgets('renders a fixture prediction without names as the bare call', (
      tester,
    ) async {
      final harness = buildPredictionHarness((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/me/fixture-predictions') {
          return okJsonList([storedFixturePrediction.toJson()]);
        }
        return okJsonList(<Object>[]);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const PredictionHistoryScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history.item.fp-1')), findsOneWidget);
      // storedFixturePrediction has no known team names and no season to
      // look them up in, so the card shows the call alone -- never the
      // raw fixture id, which read to players as a code.
      expect(find.text('f-c: 3 - 3'), findsNothing);
      expect(find.textContaining('f-c'), findsNothing);
      expect(find.text('3 - 3'), findsOneWidget);
    });

    testWidgets('shows the empty message when there is no history', (
      tester,
    ) async {
      final harness = buildPredictionHarness((request) async {
        return okJsonList(<Object>[]);
      });
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness, const PredictionHistoryScreen()));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(PredictionHistoryScreen)),
      );
      expect(find.text(l10n.predictionHistoryEmpty), findsOneWidget);
    });

    testWidgets(
      'a prediction from an earlier month keeps its teams and kickoff',
      (tester) async {
        // Last month's fixture is not in the current month's feed; its
        // names and kickoff come from the prediction's own season.
        const FixturePredictionDto lastMonth = FixturePredictionDto(
          id: 'fp-9',
          participantId: 'part-9',
          fixtureId: 'f-9',
          submittedAt: '2026-09-02T10:00:00.000Z',
          homeGoals: 2,
          awayGoals: 1,
          seasonId: 's-9',
        );
        final harness = buildPredictionHarness((request) async {
          final path = request.url.path;
          if (path == '/me/fixture-predictions') {
            return okJsonList([lastMonth.toJson()]);
          }
          if (path == '/seasons/s-9/fixtures') {
            return okJsonList([
              SeasonFixtureCardDto(
                seasonId: 's-9',
                fixtureId: 'f-9',
                homeTeam: 'Al Hilal',
                awayTeam: 'Al Nassr',
                kickoffAt: '2026-09-03T18:00:00.000Z',
              ).toJson(),
            ]);
          }
          if (path == '/seasons/s-9/fixtures/f-9/scores') {
            return okJsonObject(
              FixtureScoresDto(
                fixtureId: 'f-9',
                scores: <ParticipantFixtureScoreDto>[
                  ParticipantFixtureScoreDto(
                    fixtureId: 'f-9',
                    participantId: 'part-9',
                    rulesetVersion: 1,
                    grade: 'incorrect',
                    points: 0,
                  ),
                ],
              ).toJson(),
            );
          }
          // The current month's feed: nothing from last month in it.
          return okJsonList(<Object>[]);
        });
        addTearDown(harness.dispose);

        await tester.pumpWidget(
          _host(harness, const PredictionHistoryScreen()),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('history.item.fp-9')), findsOneWidget);
        expect(find.text(teamDisplayName('Al Hilal')), findsOneWidget);
        expect(find.text(teamDisplayName('Al Nassr')), findsOneWidget);
        expect(find.byKey(const Key('history.kickoffAt.fp-9')), findsOneWidget);
        expect(find.textContaining('f-9'), findsNothing);
        expect(
          harness.captured.map((c) => c.request.url.path),
          contains('/seasons/s-9/fixtures'),
        );

        // Completed matches keep it once the month has turned.
        await tester.tap(find.byKey(const Key('history.filter.2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('history.item.fp-9')), findsOneWidget);
      },
    );
  });
}
