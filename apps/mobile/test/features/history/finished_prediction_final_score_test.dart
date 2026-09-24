/// A finished prediction shows the recorded final score under the call,
/// with the verdict and the server's points -- through the real
/// [PredictionHistoryScreen] and the real scores read. A double that hit
/// reads "🔥 6 نقاط"; a miss "❌ 0 نقطة"; before any result, no line.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/history/prediction_history_screen.dart';
import 'package:mobile/features/history/prediction_lookup_providers.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/prediction_harness.dart' as ph;

const String _fixture = 'f-final';

FixturePredictionDto _call({required bool isDouble}) => FixturePredictionDto(
  id: 'fp-final',
  participantId: 'part-1',
  fixtureId: _fixture,
  seasonId: 's-1',
  submittedAt: '2026-09-01T10:00:00.000Z',
  homeGoals: 2,
  awayGoals: 1,
  isDouble: isDouble,
);

Future<void> _pump(
  WidgetTester tester, {
  required FixturePredictionDto prediction,
  required http.Response scores,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = ph.buildPredictionHarness((request) async {
    final String path = request.url.path;
    if (path == '/me/fixture-predictions') {
      return ph.okJsonList(<Object?>[prediction.toJson()]);
    }
    if (path == '/seasons/s-1/fixtures/$_fixture/scores') return scores;
    return ph.okJsonList(const <Object?>[]);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...harness.overrides,
        currentMonthFixturesByIdProvider.overrideWithValue(
          const AsyncData<Map<String, SeasonFixtureCardDto>>({
            _fixture: SeasonFixtureCardDto(
              seasonId: 's-1',
              fixtureId: _fixture,
              homeTeam: 'Real Madrid',
              awayTeam: 'Inter',
              kickoffAt: '2026-09-02T19:00:00.000Z',
            ),
          }),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PredictionHistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

http.Response _scores({required int points, int? home, int? away}) =>
    ph.okJsonObject(
      FixtureScoresDto(
        fixtureId: _fixture,
        scores: <ParticipantFixtureScoreDto>[
          ParticipantFixtureScoreDto(
            fixtureId: _fixture,
            participantId: 'part-1',
            rulesetVersion: 1,
            grade: points > 0 ? 'exact_scoreline' : 'incorrect',
            points: points,
          ),
        ],
        resultHomeGoals: home,
        resultAwayGoals: away,
      ).toJson(),
    );

void main() {
  const Key line = Key('history.final.fp-final');
  const Key verdict = Key('history.final.verdict');

  testWidgets('a double that hit: the final score and 🔥 6 points', (
    tester,
  ) async {
    await _pump(
      tester,
      prediction: _call(isDouble: true),
      scores: _scores(points: 6, home: 2, away: 1),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

    expect(find.byKey(line), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(line),
        matching: find.text(l10n.historyFinished),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.byKey(verdict)).data, '🔥 6 نقاط');
    expect(
      find.textContaining(l10n.historyGradeExact),
      findsNothing,
      reason: 'the verdict lives on the final line, not twice',
    );
  });

  testWidgets('a miss: ❌ 0 points', (tester) async {
    await _pump(
      tester,
      prediction: _call(isDouble: false),
      scores: _scores(points: 0, home: 1, away: 1),
    );

    expect(tester.widget<Text>(find.byKey(verdict)).data, '❌ 0 نقطة');
  });

  testWidgets('no recorded result yet: no final line', (tester) async {
    await _pump(
      tester,
      prediction: _call(isDouble: false),
      scores: _scores(points: 0),
    );

    expect(find.byKey(line), findsNothing);
  });
}
