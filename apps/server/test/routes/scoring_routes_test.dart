import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/fixtures/[id]/result/index.dart' as result_route;
// ignore: always_use_package_imports
// ignore: always_use_package_imports
import 'competition_route_harness.dart';

/// Route tests for the Scoring surface — the three routes
/// `PUT /fixtures/{id}/result`, `POST /rounds/{id}/score`, and
/// `GET /rounds/{id}/scores`.
///
/// They exercise the *real* wiring (`context.read<Future<CompositionRoot>>()`
/// → `root.<useCase>()`) over the in-memory competition + prediction + scoring
/// repositories from [competition_route_harness], so the assertions cover the
/// edge → use-case → domain → port path end-to-end, hermetically. This mirrors
/// `round_predictions_test.dart` + `season_rounds_test.dart`. It is NOT a
/// substitute for the infrastructure adapters' own tests (those live in the
/// infrastructure package) or the use-cases' own tests (application package):
/// its job is the route's status mapping, DTO shaping, admin gating, and the
/// visibility gates surfaced across the HTTP boundary.
void main() {
  // A second fixture and participant beyond the harness canon, so multi-fixture
  // / multi-participant paths are covered.
  const kFixtureId2 = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  const kOtherParticipantId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  // ---------------------------------------------------------------------------
  // PUT /fixtures/{id}/result — RecordFixtureResult (admin-only ingestion)
  // ---------------------------------------------------------------------------
  group('PUT /fixtures/{id}/result', () {
    ({CompositionRoot root, InMemoryFixtureResultRepository results})
    rootFor() {
      final results = InMemoryFixtureResultRepository();
      final root = CompositionRoot.forTesting(
        recordFixtureResult: RecordFixtureResult(
          resultRepository: results,
          clock: FixedClock(_at),
        ),
        // No fixture-level predictions are seeded either, so `ScoreFixture`
        // (Phase: احتساب فوري) resolves an empty list and scores nothing —
        // these tests exercise result recording only.
        scoreFixture: ScoreFixture(
          fixturePredictionRepository: _InMemoryFixturePredictionRepository(),
          resultRepository: results,
          scoreRepository: _InMemoryFixtureScoreRepository(),
          rulesetProvider: const ConfiguredRulesetProvider(),
        ),
      );
      return (root: root, results: results);
    }

    test(
      'an admin records a result and gets 200 with the stored scoreline',
      () async {
        final setup = rootFor();
        final response = await result_route.onRequest(
          wireContext(
            root: setup.root,
            principal: adminPrincipal(),
            method: HttpMethod.put,
            body: const {'home_goals': 2, 'away_goals': 1},
          ),
          kFixtureId,
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = await decodeBody(response);
        expect(body['fixture_id'], kFixtureId);
        expect(body['home_goals'], 2);
        expect(body['away_goals'], 1);
        // The result surface is the actual scoreline, never a score.
        expect(body.containsKey('points'), isFalse);
        // The scoreline was actually persisted behind the seam.
        final stored = await setup.results.findByFixture(
          (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>).value,
        );
        final value = (stored as Ok<FixtureResult?>).value!;
        expect(value.homeGoals, 2);
        expect(value.awayGoals, 1);
        // The clock-stamped recorded-at instant is the ingestion audit.
        expect(setup.results.recordedAt[kFixtureId], _at);
      },
    );

    test('a non-admin caller is rejected 401 (admin-only gate)', () async {
      final setup = rootFor();
      final response = await result_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          method: HttpMethod.put,
          body: const {'home_goals': 1, 'away_goals': 0},
        ),
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect((await decodeBody(response))['code'], 'auth.insufficient_role');
      // Nothing was written on the rejected path.
      expect(setup.results.count, 0);
    });

    test(
      'recording the same fixture twice is idempotent — one stored row',
      () async {
        final setup = rootFor();
        Future<Response> record(int home, int away) => result_route.onRequest(
          wireContext(
            root: setup.root,
            principal: adminPrincipal(),
            method: HttpMethod.put,
            body: {'home_goals': home, 'away_goals': away},
          ),
          kFixtureId,
        );

        expect((await record(0, 0)).statusCode, HttpStatus.ok);
        // Correct a mistyped scoreline before scoring: upsert in place.
        final second = await record(3, 2);
        expect(second.statusCode, HttpStatus.ok);
        expect(setup.results.count, 1);
        final body = await decodeBody(second);
        expect(body['home_goals'], 3);
        expect(body['away_goals'], 2);
      },
    );

    test('a negative scoreline is rejected 400 (domain validation)', () async {
      final setup = rootFor();
      final response = await result_route.onRequest(
        wireContext(
          root: setup.root,
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'home_goals': -1, 'away_goals': 0},
        ),
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(setup.results.count, 0);
    });

    test('a missing goal field is 400 (transport validation)', () async {
      final setup = rootFor();
      final response = await result_route.onRequest(
        wireContext(
          root: setup.root,
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'home_goals': 1},
        ),
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'request.field_missing');
      expect(setup.results.count, 0);
    });

    test('a non-PUT method is 405', () async {
      final setup = rootFor();
      final response = await result_route.onRequest(
        wireContext(
          root: setup.root,
          principal: adminPrincipal(),
          body: const {'home_goals': 1, 'away_goals': 0},
        ),
        kFixtureId,
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });

    test('recording a result immediately also scores the fixture itself '
        '(Phase: احتساب فوري)', () async {
      final results = InMemoryFixtureResultRepository();
      final fixturePreds = _InMemoryFixturePredictionRepository()
        ..seed(
          fixtureId: kFixtureId2,
          participantId: kOtherParticipantId,
          homeGoals: 2,
          awayGoals: 1,
        );
      final fixtureScores = _InMemoryFixtureScoreRepository();
      final root = CompositionRoot.forTesting(
        recordFixtureResult: RecordFixtureResult(
          resultRepository: results,
          clock: FixedClock(_at),
        ),
        scoreFixture: ScoreFixture(
          fixturePredictionRepository: fixturePreds,
          resultRepository: results,
          scoreRepository: fixtureScores,
          rulesetProvider: const ConfiguredRulesetProvider(),
        ),
      );

      final response = await result_route.onRequest(
        wireContext(
          root: root,
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {'home_goals': 2, 'away_goals': 1},
        ),
        kFixtureId2,
      );

      expect(response.statusCode, HttpStatus.ok);
      // Exact scoreline (2-1 predicted, 2-1 actual) = one fixture-level
      // score row, proving `ScoreFixture` ran as a side effect of
      // recording the result.
      expect(fixtureScores.count, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
}

/// A fixed UTC instant used for every clock-stamped write in these tests, so
/// recorded-at audits are deterministic.
final DateTime _at = DateTime.utc(2026, 7, 20, 9, 30);

/// A minimal in-memory [FixturePredictionRepository] for these route tests
/// only (mirrors the private fake of the same name in
/// `fixture_prediction_scoring_test.dart` — kept local, never throws).
final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final Map<String, FixturePrediction> _byKey = {};
  final List<SeasonFixture> links = [];

  static String _key(String fixtureId, String participantId) =>
      '$fixtureId|$participantId';

  void seed({
    required String fixtureId,
    required String participantId,
    required int homeGoals,
    required int awayGoals,
    bool isDouble = false,
  }) {
    final prediction =
        (FixturePrediction.submit(
                  id: const PredictionId(
                    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                  ),
                  fixture:
                      (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value,
                  participantId:
                      (ParticipantId.tryParse(participantId)
                              as Ok<ParticipantId>)
                          .value,
                  lock:
                      (FixtureLock.at(
                                kickoffAt: DateTime.utc(2026, 8, 2),
                                nowUtc: DateTime.utc(2026, 8, 1),
                              )
                              as Ok<FixtureLock>)
                          .value,
                  homeGoals: homeGoals,
                  awayGoals: awayGoals,
                  isDouble: isDouble,
                )
                as Ok<FixturePrediction>)
            .value;
    _byKey[_key(fixtureId, participantId)] = prediction;
  }

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async {
    final stored = _byKey[_key(fixture.value, participantId.value)];
    return Result.ok(
      stored == null
          ? null
          : FixturePredictionView(
              prediction: stored,
              submittedAt: DateTime.utc(2026, 7, 20),
            ),
    );
  }

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    _byKey[_key(prediction.fixture.value, prediction.participantId.value)] =
        prediction;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    _byKey[_key(prediction.fixture.value, prediction.participantId.value)] =
        prediction;
    return const Result.ok(null);
  }

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    for (final link in links) {
      if (link.seasonId == seasonId && link.fixture == fixture) {
        return Result.ok(link);
      }
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async {
    links.add(link);
    return const Result.ok(null);
  }

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async => const Result.ok(0);

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async {
    return Result.ok([
      for (final p in _byKey.values)
        if (p.fixture == fixture)
          FixturePredictionView(
            prediction: p,
            submittedAt: DateTime.utc(2026, 7, 20),
          ),
    ]);
  }

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) async {
    return Result.ok([
      for (final link in links)
        if (link.seasonId == seasonId) link.fixture,
    ]);
  }

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async =>
      const Result.ok([]);
}

/// A minimal in-memory [FixtureScoreRepository] for these route tests only.
/// Mirrors the private fake of the same name in
/// `fixture_prediction_scoring_test.dart`. Never throws.
final class _InMemoryFixtureScoreRepository implements FixtureScoreRepository {
  final Map<String, ParticipantFixtureScore> _byKey = {};

  int get count => _byKey.length;

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async {
    for (final s in scores) {
      _byKey['${s.fixture.value}|${s.participantId.value}'] = s;
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async {
    return Result.ok([
      for (final s in _byKey.values)
        if (s.fixture == fixture) s,
    ]);
  }

  @override
  Future<Result<List<ParticipantFixtureScore>>> listBySeasonFixtures(
    List<FixtureRef> fixtures,
  ) async {
    final wanted = {for (final f in fixtures) f.value};
    return Result.ok([
      for (final s in _byKey.values)
        if (wanted.contains(s.fixture.value)) s,
    ]);
  }
}
