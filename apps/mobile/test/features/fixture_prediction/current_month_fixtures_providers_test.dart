/// Unit tests for [currentMonthFixturesProvider] — the read backing the
/// regular user's unified current-month fixtures screen (Monthly
/// Competitions transition).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/current_month_fixtures_providers.dart';
import 'package:shared/shared.dart';

import '../../support/prediction_harness.dart';

const List<Map<String, Object?>> _twoItems = <Map<String, Object?>>[
  {
    'schema_version': 1,
    'competition_id': 'c-1',
    'competition_name': 'الدوري الإنجليزي الممتاز',
    'season_label': '08/2026',
    'fixture': {
      'schema_version': 1,
      'season_id': 's-1',
      'fixture_id': 'f-a',
      'home_team': 'Al Hilal',
      'away_team': 'Al Nassr',
      'kickoff_at': '2030-01-01T18:00:00.000Z',
    },
  },
  {
    'schema_version': 1,
    'competition_id': 'c-2',
    'competition_name': 'الدوري السعودي',
    'season_label': '08/2026',
    'fixture': {
      'schema_version': 1,
      'season_id': 's-2',
      'fixture_id': 'f-b',
      'home_team': null,
      'away_team': null,
      'kickoff_at': null,
    },
  },
];

void main() {
  group('currentMonthFixturesProvider', () {
    test(
      'an OK list -> the exact items, requesting GET /feed/current-month-fixtures',
      () async {
        final harness = buildPredictionHarness(
          (_) async => okJsonList(_twoItems),
        );
        addTearDown(harness.dispose);

        final result = await harness.container.read(
          currentMonthFixturesProvider.future,
        );

        expect(result, hasLength(2));
        expect(result.first.fixture.fixtureId, 'f-a');
        expect(result.first.competitionName, 'الدوري الإنجليزي الممتاز');
        expect(result.first.seasonLabel, '08/2026');
        expect(result.last.fixture.homeTeam, isNull);

        expect(harness.captured, hasLength(1));
        final request = harness.captured.single.request;
        expect(request.method, 'GET');
        expect(request.url.path, '/feed/current-month-fixtures');
      },
    );

    test('an empty list is a legitimate Ok(<empty>), not an error', () async {
      final harness = buildPredictionHarness(
        (_) async => okJsonList(const <Object?>[]),
      );
      addTearDown(harness.dispose);

      final result = await harness.container.read(
        currentMonthFixturesProvider.future,
      );

      expect(result, isEmpty);
    });

    test('a transient failure rethrows as the typed AppError', () async {
      final harness = buildPredictionHarness(
        (_) async => errorEnvelope(503, 'server.unavailable', 'down'),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.container.read(currentMonthFixturesProvider.future),
        throwsA(
          isA<AppError>().having((e) => e.kind, 'kind', ErrorKind.transient),
        ),
      );
    });
  });
}
