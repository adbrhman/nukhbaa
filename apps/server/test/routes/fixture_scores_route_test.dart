import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// ignore: always_use_package_imports
import '../../routes/seasons/[id]/fixtures/[fixtureId]/scores/index.dart'
    as scores_route;
import 'competition_route_harness.dart';

/// Route tests for `GET /seasons/{id}/fixtures/{fixtureId}/scores`
/// (docs/project-context.md, Axiom 4 Amendment — Step 1 of the 7.10.x
/// Round -> Season/Fixture migration). Mirrors
/// `fixture_prediction_scoring_test.dart`: real wiring
/// (`context.read<Future<CompositionRoot>>()` -> `root.getFixtureScores()`)
/// over local in-memory fakes for the two new ports, plus the harness's
/// existing `InMemoryCompetitionRepository`.
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

  ({CompositionRoot root, _InMemoryFixtureScoreRepository scores})
  scoresRootFor({bool joined = true, bool linked = true, bool scored = true}) {
    final compRepo = InMemoryCompetitionRepository();
    if (joined) {
      compRepo.participants.add(participant());
    }
    final predRepo = _InMemoryFixturePredictionRepository();
    if (linked) {
      predRepo.links.add(link());
    }
    final scoreRepo = _InMemoryFixtureScoreRepository();
    if (scored) {
      scoreRepo.seed(
        fixtureId: kFixtureId,
        participantId: kParticipantId,
        grade: FixtureScoreGrade.exactScoreline,
        points: 3,
      );
    }
    final root = CompositionRoot.forTesting(
      getFixtureScores: GetFixtureScores(
        competitionRepository: compRepo,
        fixturePredictionRepository: predRepo,
        fixtureScoreRepository: scoreRepo,
      ),
    );
    return (root: root, scores: scoreRepo);
  }

  group('GET /seasons/{id}/fixtures/{fixtureId}/scores', () {
    test(
      'returns the scored results for a member of a linked fixture',
      () async {
        final setup = scoresRootFor();
        final response = await scores_route.onRequest(
          wireContext(
            root: setup.root,
            principal: userPrincipal(),
            method: HttpMethod.get,
          ),
          kSeasonId,
          kFixtureId,
        );

        expect(response.statusCode, HttpStatus.ok);
        final body = await decodeBody(response);
        final scores = body['scores']! as List<Object?>;
        expect(scores, hasLength(1));
        final first = (scores.single as Map<Object?, Object?>)
            .cast<String, Object?>();
        expect(first['grade'], 'exact_scoreline');
        expect(first['points'], 3);
      },
    );

    test('returns an empty list before scoring (not an error)', () async {
      final setup = scoresRootFor(scored: false);
      final response = await scores_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        kSeasonId,
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['scores'], isEmpty);
    });

    test('rejects a non-member of the season', () async {
      final setup = scoresRootFor(joined: false);
      final response = await scores_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        kSeasonId,
        kFixtureId,
      );

      final body = await decodeBody(response);
      expect(body['code'], 'scoring.not_a_participant');
    });

    test('rejects a fixture not linked to the season', () async {
      final setup = scoresRootFor(linked: false);
      final response = await scores_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        kSeasonId,
        kFixtureId,
      );

      final body = await decodeBody(response);
      expect(body['code'], 'prediction.fixture_not_in_season');
    });

    test('405s on a non-GET method', () async {
      final setup = scoresRootFor();
      final response = await scores_route.onRequest(
        wireContext(
          root: setup.root,
          principal: userPrincipal(),
          method: HttpMethod.post,
        ),
        kSeasonId,
        kFixtureId,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}

/// A minimal in-memory [FixturePredictionRepository] for these route tests
/// only (kept local — mirrors the equivalent private class in
/// `fixture_prediction_scoring_test.dart`; not a substitute for the
/// application package's own fakes). Never throws.
final class _InMemoryFixturePredictionRepository
    implements FixturePredictionRepository {
  final List<SeasonFixture> links = [];

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
  ) async => const Result.ok([]);

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(
    SeasonId seasonId,
  ) async => const Result.ok([]);
}

/// A minimal in-memory [FixtureScoreRepository] for these route tests only.
/// Never throws.
final class _InMemoryFixtureScoreRepository implements FixtureScoreRepository {
  final Map<String, ParticipantFixtureScore> _byKey = {};

  void seed({
    required String fixtureId,
    required String participantId,
    required FixtureScoreGrade grade,
    required int points,
  }) {
    final fixture = (FixtureRef.tryParse(fixtureId) as Ok<FixtureRef>).value;
    final score = ParticipantFixtureScore.fromStored(
      fixture: fixture,
      participantId:
          (ParticipantId.tryParse(participantId) as Ok<ParticipantId>).value,
      rulesetVersion: 1,
      result: FixtureScoreResult(
        fixture: fixture,
        grade: grade,
        points: points,
      ),
    );
    _byKey['$fixtureId|$participantId'] = score;
  }

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
  ) async => Result.ok([
    for (final s in _byKey.values)
      if (s.fixture == fixture) s,
  ]);

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
