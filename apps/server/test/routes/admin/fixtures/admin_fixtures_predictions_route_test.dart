import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../../../routes/admin/fixtures/[id]/predictions/index.dart'
    as predictions_route;
import '../../competition_route_harness.dart';

/// Route tests for `GET /admin/fixtures/{id}/predictions` (docs/project-
/// context.md, Axiom 4 Amendment -- Step 3 of the 7.10.x Round -> Season/
/// Fixture migration; the per-fixture sibling of `GET /admin/rounds/{id}/
/// predictions`). Mirrors `fixture_scores_route_test.dart`: real wiring
/// (`context.read<Future<CompositionRoot>>()` -> `root.
/// adminListFixturePredictions()`) over local in-memory fakes.
///
/// This carries NO fixture-status gate (unlike the Round-side sibling,
/// gated on `scored`) -- an empty array before anyone has predicted the
/// fixture is a legitimate `200`, matching `GetFixtureScores`'s Option-3
/// philosophy. The read is audited (`fixture_predictions_viewed`).
void main() {
  const kFixtureId = '66666666-6666-6666-6666-666666666666';
  const kParticipantId = '99999999-9999-9999-9999-999999999999';
  const kPredictionId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  FixturePrediction prediction() => FixturePrediction.fromStored(
    id: (PredictionId.tryParse(kPredictionId) as Ok<PredictionId>).value,
    fixture: (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>).value,
    participantId:
        (ParticipantId.tryParse(kParticipantId) as Ok<ParticipantId>).value,
    homeGoals: 2,
    awayGoals: 1,
  );

  ({CompositionRoot root, InMemoryAuditLogRepository audit}) rootFor({
    bool predicted = true,
  }) {
    final predictions = _InMemoryFixturePredictionRepository();
    if (predicted) {
      predictions.seed(prediction());
    }
    final audit = InMemoryAuditLogRepository();
    final recorder = AuditRecorder(
      auditLog: audit,
      idGenerator: ScriptedIdGenerator([kAuditEntryId]),
      clock: FixedClock(DateTime.utc(2026, 7, 13, 12)),
    );
    final root = CompositionRoot.forTesting(
      adminListFixturePredictions: AdminListFixturePredictions(
        fixturePredictionRepository: predictions,
        auditRecorder: recorder,
      ),
      // The route joins display names onto the payload; the absent stub
      // throws rather than returning Err, so this slice must be wired. An
      // empty reader resolves no names, which is exactly the degraded case
      // the route is specified to tolerate -- the payload keeps its
      // pre-join shape.
      adminGetParticipantDisplayNames: AdminGetParticipantDisplayNames(
        participantReader: InMemoryParticipantReader(),
      ),
    );
    return (root: root, audit: audit);
  }

  Future<Response> predictionsFor(
    CompositionRoot root,
    AuthenticatedUser principal, {
    HttpMethod method = HttpMethod.get,
    Map<String, String> queryParameters = const {},
  }) => predictions_route.onRequest(
    wireContext(
      root: root,
      principal: principal,
      method: method,
      queryParameters: queryParameters,
    ),
    kFixtureId,
  );

  group('GET /admin/fixtures/{id}/predictions', () {
    test('an admin reads every prediction for the fixture', () async {
      final setup = rootFor();

      final response = await predictionsFor(setup.root, adminPrincipal());

      expect(response.statusCode, HttpStatus.ok);
      final body = await response.json() as List<Object?>;
      expect(body, hasLength(1));
      final first = (body.single as Map<Object?, Object?>)
          .cast<String, Object?>();
      expect(first['fixture_id'], kFixtureId);
      expect(first['participant_id'], kParticipantId);
      expect(first['home_goals'], 2);
      expect(first['away_goals'], 1);
      // No points/score ever leak on the raw-prediction read (Axiom 2/5).
      expect(first.containsKey('points'), isFalse);
    });

    test('an unpredicted fixture returns an empty array, still 200', () async {
      final setup = rootFor(predicted: false);

      final response = await predictionsFor(setup.root, adminPrincipal());

      expect(response.statusCode, HttpStatus.ok);
      final body = await response.json() as List<Object?>;
      expect(body, isEmpty);
    });

    test('the read is audited exactly once, attributed to the admin', () async {
      final setup = rootFor();

      await predictionsFor(setup.root, adminPrincipal());

      expect(setup.audit.entries, hasLength(1));
      final entry = setup.audit.entries.single;
      expect(entry.action, AuditAction.fixturePredictionsViewed);
      expect(entry.actorId.value, kAdminId);
      expect(entry.targetRef, kFixtureId);
    });

    test('passes an optional ?reason= through to the audit record', () async {
      final setup = rootFor();

      await predictionsFor(
        setup.root,
        adminPrincipal(),
        queryParameters: {'reason': 'user complaint'},
      );

      expect(setup.audit.entries.single.reason, 'user complaint');
    });

    test('a non-admin caller is refused before any read or audit', () async {
      final setup = rootFor();

      final response = await predictionsFor(setup.root, userPrincipal());

      final body = await decodeBody(response);
      expect(body['code'], 'auth.insufficient_role');
      expect(setup.audit.entries, isEmpty);
    });

    test('405s on a non-GET method', () async {
      final setup = rootFor();

      final response = await predictionsFor(
        setup.root,
        adminPrincipal(),
        method: HttpMethod.post,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}

/// A minimal in-memory [FixturePredictionRepository] for this route test
/// only (mirrors the equivalent private class in
/// `fixture_scores_route_test.dart`; not a substitute for the application
/// package's own fakes). Never throws.
final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final List<FixturePrediction> _predictions = [];

  void seed(FixturePrediction prediction) => _predictions.add(prediction);

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async => const Result.ok(null);

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async => const Result.ok(null);

  @override
  Future<Result<void>> linkFixtureToSeason(SeasonFixture link) async =>
      const Result.ok(null);

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async => const Result.ok(0);

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
    FixtureRef fixture,
  ) async => Result.ok([
    for (final p in _predictions)
      if (p.fixture == fixture)
        FixturePredictionView(
          prediction: p,
          submittedAt: DateTime.utc(2026, 8, 1, 12),
        ),
  ]);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(
    SeasonId seasonId,
  ) async => const Result.ok([]);

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async =>
      const Result.ok([]);
}
