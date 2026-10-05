import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/duels/challenges/[id]/accept/index.dart' as accept_route;
// ignore: always_use_package_imports
import '../../routes/duels/challenges/[id]/cancel/index.dart' as cancel_route;
// ignore: always_use_package_imports
import '../../routes/duels/challenges/[id]/decline/index.dart' as decline_route;
// ignore: always_use_package_imports
import '../../routes/duels/challenges/index.dart' as create_route;
// ignore: always_use_package_imports
import '../../routes/duels/codes/[code]/index.dart' as code_route;
// ignore: always_use_package_imports
import '../../routes/me/duels/index.dart' as my_duels_route;
import 'competition_route_harness.dart';

// Route tests for the Duel surface (migration 0090): the real routes and the
// real use-cases, wired through CompositionRoot.forTesting, over in-memory
// ports. The duel rules themselves are the database's and are tested in
// supabase/tests/0090_duels_test.sql.

const _rivalUserId = 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1';
const _rivalParticipantId = 'd2d2d2d2-d2d2-4d2d-8d2d-d2d2d2d2d2d2';
const _challengeId = 'd3d3d3d3-d3d3-4d3d-8d3d-d3d3d3d3d3d3';
const _duelId = 'd4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4';
const _code = 'ABCDEFGHJKMN';

final DateTime _now = DateTime.utc(2026, 10, 5, 12);
final DateTime _kickoff = DateTime.utc(2026, 10, 5, 18);

FixtureRef get _fixture =>
    (FixtureRef.tryParse(kFixtureId) as Ok<FixtureRef>).value;
SeasonId get _season => (SeasonId.tryParse(kSeasonId) as Ok<SeasonId>).value;
DuelCode get _duelCode => (DuelCode.tryParse(_code) as Ok<DuelCode>).value;

Participant _participant(String id, String userId) => Participant.fromStored(
  id: (ParticipantId.tryParse(id) as Ok<ParticipantId>).value,
  seasonId: _season,
  userId: (UserId.tryParse(userId) as Ok<UserId>).value,
  status: ParticipantStatus.active,
  joinedAt: DateTime.utc(2026, 10, 1),
);

DuelChallenge _challenge({
  required String challengerParticipantId,
  String? target,
}) => DuelChallenge.fromStored(
  id: const DuelChallengeId(_challengeId),
  code: _duelCode,
  seasonId: _season,
  fixture: _fixture,
  challengerParticipantId: ParticipantId(challengerParticipantId),
  targetUserId: target == null ? null : UserId(target),
  capacity: target == null ? 5 : 1,
  status: DuelChallengeStatus.open,
  createdAt: _now,
  updatedAt: _now,
);

DuelChallengePreview _preview({required String challengerUserId}) =>
    DuelChallengePreview(
      challengeId: const DuelChallengeId(_challengeId),
      code: _duelCode,
      seasonId: _season,
      fixture: _fixture,
      homeTeam: 'Home FC',
      awayTeam: 'Away FC',
      kickoffAt: _kickoff,
      challengerUserId: UserId(challengerUserId),
      challengerName: 'Ali',
      targetUserId: null,
      capacity: 5,
      acceptedCount: 0,
      status: DuelChallengeStatus.open,
      createdAt: _now,
    );

/// Records what reached the duel store; answers like the 0090 functions do
/// on the happy path.
final class _MemoryDuels implements DuelChallengeRepository {
  DuelChallenge? stored;
  int? createdCapacity;
  UserId? createdTarget;
  int acceptCalls = 0;
  UserId? cancelledBy;
  UserId? declinedBy;

  @override
  Future<Result<DuelChallenge>> createChallenge({
    required SeasonId seasonId,
    required FixtureRef fixture,
    required ParticipantId challengerParticipantId,
    required UserId? targetUserId,
    required int capacity,
    required DateTime nowUtc,
  }) async {
    createdCapacity = capacity;
    createdTarget = targetUserId;
    final challenge = _challenge(
      challengerParticipantId: challengerParticipantId.value,
      target: targetUserId?.value,
    );
    stored = challenge;
    return Result.ok(challenge);
  }

  @override
  Future<Result<DuelChallenge?>> findChallenge(DuelChallengeId id) async =>
      Result.ok(stored?.id == id ? stored : null);

  @override
  Future<Result<Duel>> acceptChallenge({
    required DuelChallengeId challengeId,
    required UserId opponentUserId,
    required DateTime nowUtc,
  }) async {
    acceptCalls++;
    return Result.ok(
      Duel.fromStored(
        id: const DuelId(_duelId),
        challengeId: challengeId,
        fixture: _fixture,
        challengerParticipantId: const ParticipantId(_rivalParticipantId),
        opponentParticipantId: const ParticipantId(kParticipantId),
        acceptedAt: nowUtc,
        createdAt: nowUtc,
      ),
    );
  }

  @override
  Future<Result<void>> cancelChallenge({
    required DuelChallengeId challengeId,
    required UserId challengerUserId,
  }) async {
    cancelledBy = challengerUserId;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> declineChallenge({
    required DuelChallengeId challengeId,
    required UserId targetUserId,
  }) async {
    declinedBy = targetUserId;
    return const Result.ok(null);
  }
}

final class _MemoryReader implements DuelReader {
  DuelChallengePreview? byCode;
  List<DuelRecord> duels = const [];

  @override
  Future<Result<DuelChallengePreview?>> findChallengeByCode(
    DuelCode code,
  ) async => Result.ok(byCode?.code == code ? byCode : null);

  @override
  Future<Result<List<DuelChallengePreview>>> listOpenChallengesFor({
    required UserId userId,
    required DateTime now,
    required int limit,
  }) async {
    final preview = byCode;
    return Result.ok(preview == null ? const [] : [preview]);
  }

  @override
  Future<Result<List<DuelRecord>>> listDuelsFor({
    required UserId userId,
    required DateTime since,
    required int limit,
  }) async => Result.ok(duels);
}

/// A minimal in-memory [FixturePredictionRepository] for these route tests
/// only. Never throws.
final class _MemoryPredictions implements FixturePredictionRepository {
  final Map<String, FixturePrediction> _byKey = {};
  final List<SeasonFixture> links = [];

  static String _key(String fixtureId, String participantId) =>
      '$fixtureId|$participantId';

  int get count => _byKey.length;

  void seed(String participantId) {
    final prediction =
        (FixturePrediction.submit(
                  id: const PredictionId(
                    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
                  ),
                  fixture: _fixture,
                  participantId:
                      (ParticipantId.tryParse(participantId)
                              as Ok<ParticipantId>)
                          .value,
                  lock:
                      (FixtureLock.at(kickoffAt: _kickoff, nowUtc: _now)
                              as Ok<FixtureLock>)
                          .value,
                  homeGoals: 1,
                  awayGoals: 0,
                  isDouble: false,
                )
                as Ok<FixturePrediction>)
            .value;
    _byKey[_key(kFixtureId, participantId)] = prediction;
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
          : FixturePredictionView(prediction: stored, submittedAt: _now),
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
  Future<Result<bool>> unlinkFixtureFromSeason({
    required SeasonId seasonId,
    required FixtureRef fixture,
  }) async => const Result.ok(false);

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
  ) async => Result.ok([
    for (final link in links)
      if (link.seasonId == seasonId) link.fixture,
  ]);

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async =>
      const Result.ok([]);
}

final class _Setup {
  _Setup({bool predicted = true}) {
    competition.participants
      ..add(_participant(kParticipantId, kUserId))
      ..add(_participant(_rivalParticipantId, _rivalUserId));
    predictions.links.add(
      (SeasonFixture.create(
                seasonId: _season,
                fixture: _fixture,
                displayOrder: 0,
              )
              as Ok<SeasonFixture>)
          .value,
    );
    if (predicted) {
      predictions.seed(kParticipantId);
    }
    schedules.seed(
      FixtureSchedule.fromStored(
        fixture: _fixture,
        homeTeam: 'Home FC',
        awayTeam: 'Away FC',
        kickoffAt: _kickoff,
      ),
    );
  }

  final InMemoryCompetitionRepository competition =
      InMemoryCompetitionRepository();
  final _MemoryPredictions predictions = _MemoryPredictions();
  final InMemoryFixtureScheduleRepository schedules =
      InMemoryFixtureScheduleRepository();
  final _MemoryDuels duels = _MemoryDuels();
  final _MemoryReader reader = _MemoryReader();

  CompositionRoot root() {
    final clock = FixedClock(_now);
    return CompositionRoot.forTesting(
      createDuelChallenge: CreateDuelChallenge(
        duels: duels,
        competition: competition,
        predictions: predictions,
        schedules: schedules,
        clock: clock,
      ),
      acceptDuelChallenge: AcceptDuelChallenge(
        duels: duels,
        submitPrediction: SubmitFixturePrediction(
          fixturePredictionRepository: predictions,
          competitionRepository: competition,
          fixtureScheduleRepository: schedules,
          idGenerator: ScriptedIdGenerator(const [
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
          ]),
          clock: clock,
        ),
        clock: clock,
      ),
      cancelDuelChallenge: CancelDuelChallenge(
        duels: duels,
        competition: competition,
      ),
      declineDuelChallenge: DeclineDuelChallenge(duels: duels),
      getDuelChallengeByCode: GetDuelChallengeByCode(
        duels: reader,
        clock: clock,
      ),
      listMyDuels: ListMyDuels(duels: reader, clock: clock),
    );
  }
}

void main() {
  group('POST /duels/challenges', () {
    test(
      'creates an open challenge and answers it read back by code',
      () async {
        final setup = _Setup();
        setup.reader.byCode = _preview(challengerUserId: kUserId);
        final response = await create_route.onRequest(
          wireContext(
            root: setup.root(),
            principal: userPrincipal(),
            body: const {'season_id': kSeasonId, 'fixture_id': kFixtureId},
          ),
        );

        expect(response.statusCode, HttpStatus.created);
        final body = await decodeBody(response);
        expect(body['code'], _code);
        expect(body['state'], 'open');
        expect(body['is_mine'], isTrue);
        expect(body['home_team'], 'Home FC');
        expect(setup.duels.createdCapacity, DuelPolicy.defaultCapacity);
        expect(setup.duels.createdTarget, isNull);
      },
    );

    test('a private challenge defaults to capacity one', () async {
      final setup = _Setup();
      setup.reader.byCode = _preview(challengerUserId: kUserId);
      final response = await create_route.onRequest(
        wireContext(
          root: setup.root(),
          principal: userPrincipal(),
          body: const {
            'season_id': kSeasonId,
            'fixture_id': kFixtureId,
            'target_user_id': _rivalUserId,
          },
        ),
      );

      expect(response.statusCode, HttpStatus.created);
      expect(setup.duels.createdCapacity, 1);
      expect(setup.duels.createdTarget, const UserId(_rivalUserId));
    });

    test('without a prediction it is refused before the store', () async {
      final setup = _Setup(predicted: false);
      final response = await create_route.onRequest(
        wireContext(
          root: setup.root(),
          principal: userPrincipal(),
          body: const {'season_id': kSeasonId, 'fixture_id': kFixtureId},
        ),
      );

      expect(response.statusCode, HttpStatus.conflict);
      final body = await decodeBody(response);
      expect(body['code'], 'social.duel_prediction_required');
      expect(setup.duels.createdCapacity, isNull);
    });

    test('a missing fixture id is 400', () async {
      final response = await create_route.onRequest(
        wireContext(
          root: _Setup().root(),
          principal: userPrincipal(),
          body: const {'season_id': kSeasonId},
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('any other method is 405', () async {
      final response = await create_route.onRequest(
        wireContext(
          root: _Setup().root(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('POST /duels/challenges/{id}/accept', () {
    test('saves the prediction, then accepts', () async {
      final setup = _Setup(predicted: false);
      setup.duels.stored = _challenge(
        challengerParticipantId: _rivalParticipantId,
      );
      final response = await accept_route.onRequest(
        wireContext(
          root: setup.root(),
          principal: userPrincipal(),
          body: const {'home_goals': 2, 'away_goals': 1},
        ),
        _challengeId,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['id'], _duelId);
      expect(body['challenge_id'], _challengeId);
      expect(setup.predictions.count, 1);
      expect(setup.duels.acceptCalls, 1);
    });

    test('an unknown challenge is refused before any prediction', () async {
      final setup = _Setup(predicted: false);
      final response = await accept_route.onRequest(
        wireContext(
          root: setup.root(),
          principal: userPrincipal(),
          body: const {'home_goals': 2, 'away_goals': 1},
        ),
        _challengeId,
      );

      expect(response.statusCode, HttpStatus.conflict);
      final body = await decodeBody(response);
      expect(body['code'], 'social.duel_challenge_not_found');
      expect(setup.predictions.count, 0);
      expect(setup.duels.acceptCalls, 0);
    });

    test('missing goals are 400', () async {
      final response = await accept_route.onRequest(
        wireContext(
          root: _Setup().root(),
          principal: userPrincipal(),
          body: const {'home_goals': 2},
        ),
        _challengeId,
      );
      expect(response.statusCode, HttpStatus.badRequest);
    });
  });

  group('cancel and decline', () {
    test('the challenger cancels', () async {
      final setup = _Setup();
      setup.duels.stored = _challenge(challengerParticipantId: kParticipantId);
      final response = await cancel_route.onRequest(
        wireContext(root: setup.root(), principal: userPrincipal()),
        _challengeId,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['status'], 'cancelled');
      expect(setup.duels.cancelledBy, const UserId(kUserId));
    });

    test('someone else cannot cancel', () async {
      final setup = _Setup();
      setup.duels.stored = _challenge(
        challengerParticipantId: _rivalParticipantId,
      );
      final response = await cancel_route.onRequest(
        wireContext(root: setup.root(), principal: userPrincipal()),
        _challengeId,
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      final body = await decodeBody(response);
      expect(body['code'], 'social.duel_not_challenger');
      expect(setup.duels.cancelledBy, isNull);
    });

    test('the invited player declines a private challenge', () async {
      final setup = _Setup();
      setup.duels.stored = _challenge(
        challengerParticipantId: _rivalParticipantId,
        target: kUserId,
      );
      final response = await decline_route.onRequest(
        wireContext(root: setup.root(), principal: userPrincipal()),
        _challengeId,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['status'], 'declined');
      expect(setup.duels.declinedBy, const UserId(kUserId));
    });
  });

  group('reads', () {
    test('GET /duels/codes/{code} answers the challenge', () async {
      final setup = _Setup();
      setup.reader.byCode = _preview(challengerUserId: _rivalUserId);
      final response = await code_route.onRequest(
        wireContext(
          root: setup.root(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        _code,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['id'], _challengeId);
      expect(body['challenger_name'], 'Ali');
      expect(body['is_mine'], isFalse);
      expect(body['state'], 'open');
    });

    test('an unknown code is not found', () async {
      final response = await code_route.onRequest(
        wireContext(
          root: _Setup().root(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        _code,
      );
      expect(response.statusCode, HttpStatus.conflict);
      final body = await decodeBody(response);
      expect(body['code'], 'social.duel_challenge_not_found');
    });

    test('GET /me/duels hides the opponent pick before kickoff', () async {
      final setup = _Setup();
      setup.reader.duels = [
        DuelRecord(
          duelId: const DuelId(_duelId),
          challengeId: const DuelChallengeId(_challengeId),
          fixture: _fixture,
          homeTeam: 'Home FC',
          awayTeam: 'Away FC',
          kickoffAt: _kickoff,
          acceptedAt: _now,
          callerIsChallenger: false,
          opponentUserId: const UserId(_rivalUserId),
          opponentName: 'Ali',
          myPick: const DuelPick(homeGoals: 2, awayGoals: 1, isDouble: false),
          opponentPick: const DuelPick(
            homeGoals: 0,
            awayGoals: 3,
            isDouble: true,
          ),
          myScore: null,
          opponentScore: null,
        ),
      ];
      final response = await my_duels_route.onRequest(
        wireContext(
          root: setup.root(),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final duels = (body['duels']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final duel = duels.single;
      expect(duel['state'], 'upcoming');
      expect(duel['my_home_goals'], 2);
      expect(duel['opponent_home_goals'], isNull);
      expect(duel['opponent_is_double'], isNull);
      expect(duel['outcome'], isNull);
    });
  });
}
