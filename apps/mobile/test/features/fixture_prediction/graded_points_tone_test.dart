/// A right outcome scores 0, so its points badge is not drawn as a success
/// -- through the real [FixturePredictionScreen], its providers and the real
/// API clients over a faked socket. An exact call keeps the success tone.
library;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ui/app_badge.dart';
import 'package:mobile/features/fixture_prediction/fixture_prediction_screen.dart';
import 'package:mobile/l10n/app_localizations.dart';

import '../../support/prediction_harness.dart';

const String _season = 's-1';
const String _fixture = 'f-1';

Future<AppBadge> _pointsBadge(
  WidgetTester tester, {
  required String grade,
  required int points,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final harness = buildPredictionHarness((request) async {
    final String path = request.url.path;
    if (path == '/seasons/$_season/fixtures') {
      return okJsonList(<Object?>[
        const SeasonFixtureCardDto(
          seasonId: _season,
          fixtureId: _fixture,
          homeTeam: 'Hilal',
          awayTeam: 'Nassr',
          kickoffAt: '2026-09-01T18:00:00.000Z',
        ).toJson(),
      ]);
    }
    if (path == '/me/fixture-predictions') {
      return okJsonList(<Object?>[
        const FixturePredictionDto(
          id: 'fp-1',
          participantId: 'part-1',
          fixtureId: _fixture,
          seasonId: _season,
          submittedAt: '2026-09-01T10:00:00.000Z',
          homeGoals: 2,
          awayGoals: 0,
          isDouble: false,
        ).toJson(),
      ]);
    }
    if (path == '/seasons/$_season/fixtures/$_fixture/scores') {
      return okJsonObject(
        FixtureScoresDto(
          fixtureId: _fixture,
          scores: <ParticipantFixtureScoreDto>[
            ParticipantFixtureScoreDto(
              fixtureId: _fixture,
              participantId: 'part-1',
              rulesetVersion: 3,
              grade: grade,
              points: points,
            ),
          ],
          resultHomeGoals: 1,
          resultAwayGoals: 0,
        ).toJson(),
      );
    }
    return okJsonList(const <Object?>[]);
  });
  addTearDown(harness.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const FixturePredictionScreen(
          seasonId: _season,
          seasonLabel: '09/2026',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<AppBadge>(
    find.byKey(const Key('fixturePrediction.points.$_fixture')),
  );
}

void main() {
  testWidgets('a right outcome (0 points) is not drawn as a success', (
    tester,
  ) async {
    final AppBadge badge = await _pointsBadge(
      tester,
      grade: 'correct_outcome',
      points: 0,
    );
    expect(badge.label, '0 نقطة');
    expect(badge.tone, AppBadgeTone.muted);
  });

  testWidgets('an exact call keeps the success tone', (tester) async {
    final AppBadge badge = await _pointsBadge(
      tester,
      grade: 'exact_scoreline',
      points: 3,
    );
    expect(badge.tone, AppBadgeTone.success);
  });
}
