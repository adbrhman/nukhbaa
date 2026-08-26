/// Unit tests for [seasonFixturesProvider] — the fixture-list read for the
/// per-fixture prediction flow (Axiom 4 Amendment).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/fixture_prediction/fixture_prediction_providers.dart';
import 'package:shared/shared.dart';

import '../../support/prediction_harness.dart';

const List<Map<String, Object?>> _twoFixtures = <Map<String, Object?>>[
  {
    'schema_version': 1,
    'season_id': 's-1',
    'fixture_id': 'f-a',
    'home_team': 'Al Hilal',
    'away_team': 'Al Nassr',
    'kickoff_at': '2030-01-01T18:00:00.000Z',
  },
  {
    'schema_version': 1,
    'season_id': 's-1',
    'fixture_id': 'f-b',
    'home_team': null,
    'away_team': null,
    'kickoff_at': null,
  },
];

void main() {
  group('seasonFixturesProvider', () {
    test(
      'an OK list -> the exact fixtures, requesting GET /seasons/{id}/fixtures',
      () async {
        final harness = buildPredictionHarness(
          (_) async => okJsonList(_twoFixtures),
        );
        addTearDown(harness.dispose);

        final result = await harness.container.read(
          seasonFixturesProvider('s-1').future,
        );

        expect(result, hasLength(2));
        expect(result.first.fixtureId, 'f-a');
        expect(result.last.homeTeam, isNull);

        expect(harness.captured, hasLength(1));
        final request = harness.captured.single.request;
        expect(request.method, 'GET');
        expect(request.url.path, '/seasons/s-1/fixtures');
      },
    );

    test('an empty list is a legitimate Ok(<empty>), not an error', () async {
      final harness = buildPredictionHarness(
        (_) async => okJsonList(const <Object?>[]),
      );
      addTearDown(harness.dispose);

      final result = await harness.container.read(
        seasonFixturesProvider('s-empty').future,
      );

      expect(result, isEmpty);
    });

    test('a transient failure rethrows as the typed AppError', () async {
      final harness = buildPredictionHarness(
        (_) async => errorEnvelope(503, 'server.unavailable', 'down'),
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.container.read(seasonFixturesProvider('s-1').future),
        throwsA(
          isA<AppError>().having((e) => e.kind, 'kind', ErrorKind.transient),
        ),
      );
    });
  });
}
