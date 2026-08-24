#!/usr/bin/env bash
# Phase 5 — Routes expand (Axiom 4 Amendment: Round -> monthly competition).
# Additive only: two new routes (submit/amend a fixture prediction, score a
# fixture) + two new DTO mappers + a route test, alongside every round route.
# Wires composition_root.dart via a python anchor-patch (additive: new
# required fields inserted next to their round-scoped siblings — same
# technique phase 3 used on scoring.dart). "دمج المباريات" (GET
# /feed/matches) needs no work — already wired and already consumed by
# apps/mobile (confirmed by inspection).
set -euo pipefail
cd "${1:-.}"

mkdir -p "apps/server/routes/seasons/[id]/fixtures/[fixtureId]/prediction"
mkdir -p "apps/server/routes/fixtures/[id]/score"
mkdir -p apps/server/lib/http
mkdir -p apps/server/test/routes

# ---------------------------------------------------------------------------
# apps/server/routes/seasons/[id]/fixtures/[fixtureId]/prediction/index.dart
# ---------------------------------------------------------------------------
cat > "apps/server/routes/seasons/[id]/fixtures/[fixtureId]/prediction/index.dart" <<'NUKHBA_EOF'
import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_prediction_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /seasons/{id}/fixtures/{fixtureId}/prediction` — submit (or
/// idempotently amend) the caller's prediction for a single fixture (API ADR
/// §2: command intent `SubmitFixturePrediction`; docs/project-context.md,
/// Axiom 4 Amendment — the per-fixture sibling of `POST
/// /rounds/{id}/predictions`, so one fixture — or more, one call each — can be
/// predicted and later scored without waiting on a round to close).
///
/// The body is a [FixturePredictionCommandDto] (predicted scoreline + the
/// optional `is_double` flag only); the participant is resolved server-side
/// from the verified principal and the season named in the path, **never**
/// from the body (Security ADR §2 / Axiom 2). Points are never accepted or
/// returned. Returns the stored [FixturePredictionDto] (`200`) — one row per
/// `(fixture, participant)` (Axiom 4 Amendment), so both a first submission
/// and an amendment resolve to the same resource.
///
/// The whole `/seasons` subtree is already behind `bearerAuth`
/// (`routes/seasons/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String fixtureId,
) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final homeResult = requireInt(body, 'home_goals');
  if (homeResult is Err<int>) {
    return errorResponse(homeResult.error);
  }
  final awayResult = requireInt(body, 'away_goals');
  if (awayResult is Err<int>) {
    return errorResponse(awayResult.error);
  }
  final isDoubleResult = _optionalBool(body, 'is_double');
  if (isDoubleResult is Err<bool>) {
    return errorResponse(isDoubleResult.error);
  }

  final result = await root.submitFixturePrediction(
    principal: principal,
    seasonId: id,
    fixtureId: fixtureId,
    homeGoals: (homeResult as Ok<int>).value,
    awayGoals: (awayResult as Ok<int>).value,
    isDouble: (isDoubleResult as Ok<bool>).value,
  );

  return switch (result) {
    Ok<FixturePredictionView>(:final value) => Response.json(
      body: fixturePredictionViewToJson(value),
    ),
    Err<FixturePredictionView>(:final error) => errorResponse(error),
  };
}

/// Extracts an optional boolean field, defaulting to `false` when absent —
/// mirrors the inline `is_double` parsing in
/// `routes/rounds/[id]/predictions/index.dart`'s `_parseScores`. A present but
/// wrongly-typed value is still a transport-validation failure (400).
Result<bool> _optionalBool(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) {
    return const Result.ok(false);
  }
  if (value is bool) {
    return Result.ok(value);
  }
  return Result.err(
    AppError.validation(
      'request.field_missing',
      'Field "$field", when present, must be a boolean',
    ),
  );
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# apps/server/routes/fixtures/[id]/score/index.dart
# ---------------------------------------------------------------------------
cat > "apps/server/routes/fixtures/[id]/score/index.dart" <<'NUKHBA_EOF'
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_score_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /fixtures/{id}/score` — score every prediction recorded for a single
/// fixture (API ADR §2: command intent `ScoreFixture`; docs/project-context.md,
/// Axiom 4 Amendment — "ScoreFixture replaces ScoreRound", the per-fixture
/// sibling of `POST /rounds/{id}/score`, so a fixture's predictions can be
/// graded the instant its actual result lands — never waiting on the rest of
/// any round). Admin-only, enforced inside the use-case (Axioms 2/5: only the
/// platform computes and writes points).
///
/// No request body: the actual scoreline was already ingested separately by
/// the admin `PUT /fixtures/{id}/result` command, and points are computed
/// server-side from the platform's current ruleset (see the reproducibility
/// gap noted on `ScoreFixture` — unlike `ScoreRound` there is no frozen
/// per-round snapshot to replay yet).
///
/// Idempotent: re-scoring an already-scored fixture recomputes the same
/// deterministic result and re-persists it in place, never duplicating rows.
/// Returns the computed [FixtureScoresDto] (`200`); a fixture with no
/// predictions surfaces as `409` `scoring.fixture_has_no_predictions` via the
/// shared error envelope.
///
/// The `/fixtures` subtree is already behind `bearerAuth`
/// (`routes/fixtures/_middleware.dart`), which provides the verified
/// [AuthenticatedUser]; an unauthenticated request never reaches this handler.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.scoreFixture(principal: principal, fixtureId: id);

  return switch (result) {
    Ok<List<ParticipantFixtureScore>>(:final value) => Response.json(
      body: fixtureScoresToJson(id, value),
    ),
    Err<List<ParticipantFixtureScore>>(:final error) => errorResponse(error),
  };
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# apps/server/lib/http/fixture_prediction_dto_mapper.dart
# ---------------------------------------------------------------------------
cat > 'apps/server/lib/http/fixture_prediction_dto_mapper.dart' <<'NUKHBA_EOF'
import 'package:application/application.dart';
import 'package:contracts/contracts.dart';

/// Projects a [FixturePredictionView] (a fixture-prediction aggregate plus the
/// submission instant the repository stamped) onto the versioned wire shape
/// [FixturePredictionDto] (API ADR §4) — the per-fixture sibling of
/// `predictionViewToJson` (docs/project-context.md, Axiom 4 Amendment).
///
/// Integrity boundary (Axioms 2/5): only the user's stored *intent* crosses
/// the wire — the fixture id and predicted goals, plus the `is_double` flag.
/// No points, score, or competitive-record value is ever included; those are
/// produced server-side by `ScoreFixture` and never part of this read model.
/// `submitted_at` is the exact instant the repository stamped (carried on the
/// view), never fabricated at the edge.
Map<String, Object?> fixturePredictionViewToJson(FixturePredictionView view) {
  final prediction = view.prediction;
  return FixturePredictionDto(
    id: prediction.id.value,
    participantId: prediction.participantId.value,
    fixtureId: prediction.fixture.value,
    submittedAt: view.submittedAt.toIso8601String(),
    homeGoals: prediction.homeGoals,
    awayGoals: prediction.awayGoals,
    isDouble: prediction.isDouble,
  ).toJson();
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# apps/server/lib/http/fixture_score_dto_mapper.dart
# ---------------------------------------------------------------------------
cat > 'apps/server/lib/http/fixture_score_dto_mapper.dart' <<'NUKHBA_EOF'
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects the domain [ParticipantFixtureScore] aggregate onto the versioned
/// wire shape [ParticipantFixtureScoreDto] (API ADR §4), and a fixture's whole
/// list onto [FixtureScoresDto] — the per-fixture sibling of
/// `roundScoreToDto`/`roundScoresToJson` (docs/project-context.md, Axiom 4
/// Amendment).
///
/// Integrity boundary (Axioms 2/5): a score is a **server-produced read
/// value** — the grade token and points are echoed exactly as the domain
/// scoring function computed them; nothing here is client-writable. The grade
/// crosses the wire as its stable [FixtureScoreGrade.wireValue] token, never a
/// Dart enum name. Names a fixture by id only (Axiom 3); carries no
/// round/group reference (Axiom 4).
ParticipantFixtureScoreDto fixtureScoreToDto(
  ParticipantFixtureScore score, {
  String displayName = '',
}) {
  return ParticipantFixtureScoreDto(
    fixtureId: score.fixture.value,
    participantId: score.participantId.value,
    rulesetVersion: score.rulesetVersion,
    grade: score.result.grade.wireValue,
    points: score.points,
    displayName: displayName,
  );
}

/// Shapes every participant's [ParticipantFixtureScore] for a fixture into the
/// whole-fixture read response [FixtureScoresDto]. [fixtureId] is the
/// requested fixture (the same fixture every score shares).
Map<String, Object?> fixtureScoresToJson(
  String fixtureId,
  List<ParticipantFixtureScore> scores, {
  Map<String, String> displayNames = const {},
}) {
  return FixtureScoresDto(
    fixtureId: fixtureId,
    scores: [
      for (final score in scores)
        fixtureScoreToDto(
          score,
          displayName: displayNames[score.participantId.value] ?? '',
        ),
    ],
  ).toJson();
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# apps/server/test/routes/fixture_prediction_scoring_test.dart
# (hermetic — local in-memory fakes; reuses competition_route_harness for
# InMemoryCompetitionRepository/InMemoryFixtureResultRepository/wireContext/
# adminPrincipal/userPrincipal/kSeasonId/kUserId/kAdminId/decodeBody)
# ---------------------------------------------------------------------------
cat > 'apps/server/test/routes/fixture_prediction_scoring_test.dart' <<'NUKHBA_EOF'
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
                fixture: (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>)
                    .value,
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
    test('inserts a new prediction and returns 200 with the stored DTO', () async {
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
    });

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
        resultRepo.results[kFixtureId] = FixtureResult.fromStored(
          fixture: (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>).value,
          homeGoals: 2,
          awayGoals: 1,
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

    test('is idempotent — re-scoring replaces in place, never duplicates', () async {
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
    });

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
                  id: const PredictionId('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'),
                  fixture: (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>)
                      .value,
                  participantId:
                      (ParticipantId.tryParse(participantId)
                              as Ok<ParticipantId>)
                          .value,
                  lock: (FixtureLock.at(
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
}
NUKHBA_EOF

# ---------------------------------------------------------------------------
# Patch composition_root.dart (additive: new required constructor params +
# forTesting optional params/defaults + absent factories + fields + real
# wiring + Unwired port classes). Mirrors Phase 3's scoring.dart patch style.
# ---------------------------------------------------------------------------
python3 - <<'PYEOF'
import pathlib

p = pathlib.Path('apps/server/lib/composition/composition_root.dart')
s = p.read_text()

def replace_once(old, new, label):
    global s
    n = s.count(old)
    assert n == 1, f'anchor "{label}" matched {n} times (expected 1)'
    s = s.replace(old, new, 1)

# 1. Required constructor params.
replace_once(
    "    required this.submitPrediction,\n",
    "    required this.submitPrediction,\n"
    "    required this.submitFixturePrediction,\n",
    "ctor submitPrediction",
)
replace_once(
    "    required this.scoreRound,\n",
    "    required this.scoreRound,\n"
    "    required this.scoreFixture,\n",
    "ctor scoreRound",
)

# 2. forTesting optional params.
replace_once(
    "    SubmitPrediction? submitPrediction,\n",
    "    SubmitPrediction? submitPrediction,\n"
    "    SubmitFixturePrediction? submitFixturePrediction,\n",
    "forTesting submitPrediction",
)
replace_once(
    "    ScoreRound? scoreRound,\n",
    "    ScoreRound? scoreRound,\n"
    "    ScoreFixture? scoreFixture,\n",
    "forTesting scoreRound",
)

# 3. forTesting default-assignment initializers.
replace_once(
    "       submitPrediction = submitPrediction ?? _absentSubmitPrediction(),\n",
    "       submitPrediction = submitPrediction ?? _absentSubmitPrediction(),\n"
    "       submitFixturePrediction =\n"
    "           submitFixturePrediction ?? _absentSubmitFixturePrediction(),\n",
    "init submitPrediction",
)
replace_once(
    "       scoreRound = scoreRound ?? _absentScoreRound(),\n",
    "       scoreRound = scoreRound ?? _absentScoreRound(),\n"
    "       scoreFixture = scoreFixture ?? _absentScoreFixture(),\n",
    "init scoreRound",
)

# 4. Unwired repository fields + absent factories (prediction side), placed
#    right after the existing _absentListMyPredictions factory.
old_pred_anchor = (
    "  static ListMyPredictions _absentListMyPredictions() =>\n"
    "      ListMyPredictions(predictionRepository: _unwiredPredictionRepository);\n"
)
assert old_pred_anchor in s, 'anchor _absentListMyPredictions not found'
new_pred_block = old_pred_anchor + '''
  /// Backs the "absent" fixture-prediction use-case, so a test that reaches
  /// an unwired Axiom-4-Amendment prediction slice fails loudly instead of
  /// touching a real database.
  static final FixturePredictionRepository
  _unwiredFixturePredictionRepository = _UnwiredFixturePredictionRepository();

  static SubmitFixturePrediction _absentSubmitFixturePrediction() =>
      SubmitFixturePrediction(
        fixturePredictionRepository: _unwiredFixturePredictionRepository,
        competitionRepository: _unwiredCompetitionRepository,
        fixtureScheduleRepository: _unwiredFixtureScheduleRepository,
        idGenerator: _unwiredIdGenerator,
        clock: _unwiredClock,
      );
'''
s = s.replace(old_pred_anchor, new_pred_block, 1)

# 5. Unwired repository field + absent factory (scoring side), placed right
#    after the existing _absentScoreRoundsForFixture factory.
old_score_anchor = (
    "  static ScoreRoundsForFixture _absentScoreRoundsForFixture() =>\n"
    "      ScoreRoundsForFixture(\n"
    "        competitionRepository: _unwiredCompetitionRepository,\n"
    "        scoreRound: _absentScoreRound(),\n"
    "      );\n"
)
assert old_score_anchor in s, 'anchor _absentScoreRoundsForFixture not found'
new_score_block = old_score_anchor + '''
  /// Backs the "absent" fixture-scoring use-case, so a test that reaches an
  /// unwired Axiom-4-Amendment scoring slice fails loudly instead of touching
  /// a real database.
  static final FixtureScoreRepository _unwiredFixtureScoreRepository =
      _UnwiredFixtureScoreRepository();

  static ScoreFixture _absentScoreFixture() => ScoreFixture(
    fixturePredictionRepository: _unwiredFixturePredictionRepository,
    resultRepository: _unwiredFixtureResultRepository,
    scoreRepository: _unwiredFixtureScoreRepository,
    rulesetProvider: _unwiredRulesetProvider,
  );
'''
s = s.replace(old_score_anchor, new_score_block, 1)

# 6. Public fields.
old_field_pred = "  /// Submits (or idempotently amends) the caller's prediction for a round.\n  final SubmitPrediction submitPrediction;\n"
assert old_field_pred in s, 'field submitPrediction anchor not found'
new_field_pred = old_field_pred + '''
  /// Submits (or idempotently amends) the caller's prediction for a single
  /// fixture (Axiom 4 Amendment; per-fixture sibling of [submitPrediction]).
  final SubmitFixturePrediction submitFixturePrediction;
'''
s = s.replace(old_field_pred, new_field_pred, 1)

old_field_score = (
    "  /// Scores every prediction in a locked round (admin-only command; the points\n"
    "  /// are computed and written server-side — Axioms 2/5).\n"
    "  final ScoreRound scoreRound;\n"
)
assert old_field_score in s, 'field scoreRound anchor not found'
new_field_score = old_field_score + '''
  /// Scores every prediction recorded for a single fixture (Axiom 4
  /// Amendment; "ScoreFixture replaces ScoreRound" — per-fixture sibling of
  /// [scoreRound], admin-only, computed and written server-side).
  final ScoreFixture scoreFixture;
'''
s = s.replace(old_field_score, new_field_score, 1)

# 7. Real repository instantiation.
old_repo_pred = "    final predictionRepository = PostgresPredictionRepository(connection);\n"
assert old_repo_pred in s, 'repo instantiation anchor (prediction) not found'
new_repo_pred = old_repo_pred + '''
    // Axiom 4 Amendment: the per-fixture Prediction context, its own
    // Postgres-backed repository (kept separate, same reasoning as
    // predictionRepository above).
    final fixturePredictionRepository = PostgresFixturePredictionRepository(
      connection,
    );
'''
s = s.replace(old_repo_pred, new_repo_pred, 1)

old_repo_score = "    final scoreRepository = PostgresScoreRepository(connection);\n"
assert old_repo_score in s, 'repo instantiation anchor (score) not found'
new_repo_score = old_repo_score + '''
    // Axiom 4 Amendment: the per-fixture Scoring context, its own
    // Postgres-backed repository (kept separate, same reasoning as
    // scoreRepository above).
    final fixtureScoreRepository = PostgresFixtureScoreRepository(connection);
'''
s = s.replace(old_repo_score, new_repo_score, 1)

# 8. Real wiring block entries.
old_wire_pred = (
    "      submitPrediction: SubmitPrediction(\n"
    "        predictionRepository: predictionRepository,\n"
    "        competitionRepository: competitionRepository,\n"
    "        fixtureScheduleRepository: fixtureScheduleRepository,\n"
    "        idGenerator: idGenerator,\n"
    "        clock: clock,\n"
    "      ),\n"
)
assert old_wire_pred in s, 'wiring anchor (submitPrediction) not found'
new_wire_pred = old_wire_pred + '''      submitFixturePrediction: SubmitFixturePrediction(
        fixturePredictionRepository: fixturePredictionRepository,
        competitionRepository: competitionRepository,
        fixtureScheduleRepository: fixtureScheduleRepository,
        idGenerator: idGenerator,
        clock: clock,
      ),
'''
s = s.replace(old_wire_pred, new_wire_pred, 1)

old_wire_score = (
    "      scoreRound: ScoreRound(\n"
    "        competitionRepository: competitionRepository,\n"
    "        predictionRepository: predictionRepository,\n"
    "        resultRepository: fixtureResultRepository,\n"
    "        scoreRepository: scoreRepository,\n"
    "      ),\n"
)
assert old_wire_score in s, 'wiring anchor (scoreRound) not found'
new_wire_score = old_wire_score + '''      scoreFixture: ScoreFixture(
        fixturePredictionRepository: fixturePredictionRepository,
        resultRepository: fixtureResultRepository,
        scoreRepository: fixtureScoreRepository,
        rulesetProvider: rulesetProvider,
      ),
'''
s = s.replace(old_wire_score, new_wire_score, 1)

# 9. _Unwired* port classes (thrown-on-touch), placed after the existing
#    _UnwiredPredictionRepository / _UnwiredScoreRepository classes.
old_unwired_pred = (
    "  @override\n"
    "  Future<Result<List<RoundFixture>>> listRoundFixtures(RoundId roundId) =>\n"
    "      _unwired();\n"
    "}\n"
)
assert s.count(old_unwired_pred) == 1, 'anchor _UnwiredPredictionRepository tail not found/unique'
new_unwired_pred = old_unwired_pred + '''
/// Backs the "absent" fixture-prediction use-case's port (Axiom 4 Amendment):
/// any method throws so a test that reaches an unwired slice fails loudly
/// instead of touching a real database.
final class _UnwiredFixturePredictionRepository
    implements FixturePredictionRepository {
  static Never _unwired() => throw StateError(
    'A fixture-prediction use-case was not wired into this root',
  );

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) => _unwired();

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) => _unwired();

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) => _unwired();

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) => _unwired();

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) => _unwired();

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) => _unwired();
}
'''
s = s.replace(old_unwired_pred, new_unwired_pred, 1)

old_unwired_score = (
    "  @override\n"
    "  Future<Result<List<RoundScore>>> listByRound(RoundId roundId) => _unwired();\n"
    "}\n"
)
assert s.count(old_unwired_score) == 1, 'anchor _UnwiredScoreRepository tail not found/unique'
new_unwired_score = old_unwired_score + '''
/// Backs the "absent" fixture-scoring use-case's port (Axiom 4 Amendment): any
/// method throws so a test that reaches an unwired slice fails loudly instead
/// of touching a real database.
final class _UnwiredFixtureScoreRepository implements FixtureScoreRepository {
  static Never _unwired() => throw StateError(
    'A fixture-scoring use-case was not wired into this root',
  );

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) => _unwired();

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) => _unwired();
}
'''
s = s.replace(old_unwired_score, new_unwired_score, 1)

p.write_text(s)
print('composition_root.dart patched OK')
PYEOF

echo "DONE — الآن نفّذ:"
echo "  flutter pub get"
echo "  dart analyze apps/server"
echo "  flutter test apps/server --exclude-tags=integration"
