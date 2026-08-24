import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/fixtures/[id]/score/index.dart' as score_route;
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/[fixtureId]/prediction/index.dart'
    as prediction_route;
import 'competition_route_harness.dart';

/// Route tests for the per-fixture Prediction/Scoring surface —
/// `POST /seasons/{id}/fixtures/{fixtureId}/prediction` and
/// `POST /fixtures/{id}/score` (docs/project-context.md, Axiom 4 Amendment).
///
/// Mirrors `round_predictions_test.dart` + `scoring_routes_test.dart`: real
/// wiring (`context.read<Future<CompositionRoot>>()` -> `root.<useCase>()`)
/// over local in-memory fakes for the two new ports, plus the harness's
/// existing `InMemoryCompetitionRepository` (season/participant resolution)
/// and `InMemoryFixtureResultRepository` (actual scoreline). NOT a substitute
/// for the use-cases' own tests (application package) or the adapters' own
/// tests (infrastructure package).
void main() {
  const kFixtureId = '66666666-6666-6666-6666-666666666666';
  const kParticipantId = '99999999-9999-9999-9999-999999999999';

  Participant participant() => Participant.fromStored(
    id: (ParticipantId.tryParse(kParticipantId) as Ok<ParticipantId>).value,
    seasonId: (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
    userId: (UserId.tryParse(kUserId) as Ok<UserId>).value,
    status: ParticipantStatus.active,
    joinedAt: DateTime.utc(2026, 7, 1),
  );

  SeasonFixture link() =>
      (SeasonFixture.create(
                seasonId: (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value,
                fixture:
                    (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>).value,
                displayOrder: 0,
              )
              as Ok<SeasonFixture>)
          .value;

  ({CompositionRoot root, _InMemoryFixturePredictionRepository preds})
  predictionRootFor({bool joined = true, bool linked = true}) {
    final compRepo = InMemoryCompetitionRepository();
    if (joined) {
      compRepo.participants.add(participant());
    }
    final predRepo = _InMemoryFixturePredictionRepository();
    if (linked) {
      predRepo.links.add(link());
    }
    final root = CompositionRoot.forTesting(
      submitFixturePrediction: SubmitFixturePrediction(
        fixturePredictionRepository: predRepo,
        competitionRepository: compRepo,
        fixtureScheduleRepository: InMemoryFixtureScheduleRepository(),
        idGenerator: ScriptedIdGenerator(const [
          'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        ]),
        clock: FixedClock(DateTime.utc(2026, 7, 20, 9, 30)),
      ),
    );
    return (root: root, preds: predRepo);
  }

  group('POST /seasons/{id}/fixtures/{fixtureId}/prediction', () {
    test(
      'inserts a new prediction and returns 200 with the stored DTO',
      () async {
        final setup = predictionRootFor();
        final context = wireContext(
          root: setup.root,
          principal: userPrincipal(),
          body: const {'home_goals': 2, 'away_goals': 1, 'is_double': true},
        );

        final response = await prediction_route.onRequest(
          context,
          kSeasonId,
          kFixtureId,
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = await decodeBody(response);
        expect(body['home_goals'], 2);
        expect(body['away_goals'], 1);
        expect(body['is_double'], isTrue);
        expect(body['fixture_id'], kFixtureId);
        expect(body.containsKey('points'), isFalse);
        expect(setup.preds.count, 1);
      },
    );

    test('amends the same row on a repeat submission', () async {
      final setup = predictionRootFor();
      await prediction_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          body: const {'home_goals': 2, 'away_goals': 1},
        ),
        kSeasonId,
        kFixtureId,
      );

      final response = await prediction_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          body: const {'home_goals': 0, 'away_goals': 0},
        ),
        kSeasonId,
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(setup.preds.count, 1);
    });

    test('rejects a fixture not linked to the season', () async {
      final setup = predictionRootFor(linked: false);
      final response = await prediction_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          body: const {'home_goals': 1, 'away_goals': 0},
        ),
        kSeasonId,
        kFixtureId,
      );

      final body = await decodeBody(response);
      expect(body['code'], 'prediction.fixture_not_in_season');
    });

    test('rejects a malformed body (missing home_goals)', () async {
      final setup = predictionRootFor();
      final response = await prediction_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          body: const {'away_goals': 0},
        ),
        kSeasonId,
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('405s on a non-POST method', () async {
      final setup = predictionRootFor();
      final response = await prediction_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        kSeasonId,
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('POST /fixtures/{id}/score', () {
    ({CompositionRoot root, _InMemoryFixtureScoreRepository scores})
    scoreRootFor({bool withPrediction = true, bool withResult = true}) {
      final predRepo = _InMemoryFixturePredictionRepository();
      if (withPrediction) {
        predRepo.seed(
          fixtureId: kFixtureId,
          participantId: kParticipantId,
          homeGoals: 2,
          awayGoals: 1,
        );
      }
      final resultRepo = InMemoryFixtureResultRepository();
      if (withResult) {
        resultRepo.upsert(
          FixtureResult.fromStored(
            fixture: (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>).value,
            homeGoals: 2,
            awayGoals: 1,
          ),
          DateTime.utc(2026, 8, 1),
        );
      }
      final scoreRepo = _InMemoryFixtureScoreRepository();
      final root = CompositionRoot.forTesting(
        scoreFixture: ScoreFixture(
          fixturePredictionRepository: predRepo,
          resultRepository: resultRepo,
          scoreRepository: scoreRepo,
          rulesetProvider: const ConfiguredRulesetProvider(),
        ),
      );
      return (root: root, scores: scoreRepo);
    }

    test('grades an exact-scoreline prediction and returns 200', () async {
      final setup = scoreRootFor();
      final response = await score_route.onRequest(
        wireContext(root: setup.root, principal: adminPrincipal()),
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final scores = body['scores']! as List<Object?>;
      expect(scores, hasLength(1));
      final first = (scores.single as Map<Object?, Object?>)
          .cast<String, Object?>();
      expect(first['grade'], 'exact_scoreline');
      expect(setup.scores.count, 1);
    });

    test(
      'is idempotent — re-scoring replaces in place, never duplicates',
      () async {
        final setup = scoreRootFor();
        await score_route.onRequest(
          wireContext(root: setup.root, principal: adminPrincipal()),
          kFixtureId,
        );
        await score_route.onRequest(
          wireContext(root: setup.root, principal: adminPrincipal()),
          kFixtureId,
        );

        expect(setup.scores.count, 1);
      },
    );

    test('rejects a non-admin caller', () async {
      final setup = scoreRootFor();
      final response = await score_route.onRequest(
        wireContext(root: setup.root, principal: userPrincipal()),
        kFixtureId,
      );

      final body = await decodeBody(response);
      expect(body['code'], isNot('scoring.fixture_has_no_predictions'));
      expect(response.statusCode, isNot(HttpStatus.ok));
    });

    test('rejects a fixture with no predictions', () async {
      final setup = scoreRootFor(withPrediction: false);
      final response = await score_route.onRequest(
        wireContext(root: setup.root, principal: adminPrincipal()),
        kFixtureId,
      );

      final body = await decodeBody(response);
      expect(body['code'], 'scoring.fixture_has_no_predictions');
    });

    test('405s on a non-POST method', () async {
      final setup = scoreRootFor();
      final response = await score_route.onRequest(
        wireContext(
          root: setup.root,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}

/// A minimal in-memory [FixturePredictionRepository] for these route tests
/// only (kept local — not a substitute for the application package's own
/// fakes). Never throws.
final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final Map<String, FixturePrediction> _byKey = {};
  final List<SeasonFixture> links = [];

  static String _key(String fixtureId, String participantId) =>
      '$fixtureId|$participantId';

  int get count => _byKey.length;

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
}

/// A minimal in-memory [FixtureScoreRepository] for these route tests only.
/// Never throws.
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
