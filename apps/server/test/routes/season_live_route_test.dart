import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/seasons/[id]/live/index.dart' as route;
import 'competition_route_harness.dart';

const _rival = '99999999-9999-9999-9999-999999999999';

final DateTime _now = DateTime.utc(2026, 10, 6, 19);

final class _Predictions extends Mock implements FixturePredictionRepository {}

final class _Totals implements FixtureTotalsReader {
  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async => Result.ok([
    (ParticipantFixtureTotals.of(
              participantId: const ParticipantId(_rival),
              totalPoints: 3,
              fixturesScored: 2,
              exactCount: 1,
              decidedCount: 1,
            )
            as Ok<ParticipantFixtureTotals>)
        .value,
  ]);
}

final class _Rules implements RulesetProvider {
  @override
  Future<Result<RulesetSnapshot>> currentSnapshotFor(FormatType format) async =>
      RulesetSnapshot.create(
        payload: const {
          'format': 'football_scoreline',
          'double_multiplier': 2,
          'points': {
            'exact_scoreline': 3,
            'correct_outcome': 0,
            'incorrect': 0,
          },
        },
        rulesetVersion: 3,
      );
}

final class _Duels implements DuelReader {
  @override
  Future<Result<DuelChallengePreview?>> findChallengeByCode(
    DuelCode code,
  ) async => const Result.ok(null);

  @override
  Future<Result<List<DuelChallengePreview>>> listOpenChallengesFor({
    required UserId userId,
    required DateTime now,
    required int limit,
  }) async => const Result.ok(<DuelChallengePreview>[]);

  @override
  Future<Result<List<DuelRecord>>> listDuelsFor({
    required UserId userId,
    required DateTime since,
    required int limit,
  }) async => Result.ok([
    DuelRecord(
      duelId: const DuelId('51111111-1111-1111-1111-111111111111'),
      challengeId: const DuelChallengeId(
        '52222222-1111-1111-1111-111111111111',
      ),
      fixture: const FixtureRef(kFixtureId),
      homeTeam: 'Home',
      awayTeam: 'Away',
      kickoffAt: _now.subtract(const Duration(hours: 1)),
      acceptedAt: _now.subtract(const Duration(hours: 2)),
      callerIsChallenger: true,
      opponentUserId: const UserId(kNonMemberUserId),
      opponentName: 'Rival',
      myPick: const DuelPick(homeGoals: 2, awayGoals: 1, isDouble: false),
      opponentPick: const DuelPick(homeGoals: 0, awayGoals: 0, isDouble: false),
      myScore: null,
      opponentScore: null,
    ),
  ]);
}

final class _Board implements LiveScoreBoard {
  @override
  void put(Map<String, LiveScore> scores) {}

  @override
  void remove(Iterable<String> fixtureIds) {}

  @override
  Map<String, LiveScore> read(Iterable<String> fixtureIds) => {
    kFixtureId: LiveScore(
      homeGoals: 2,
      awayGoals: 1,
      minute: 70,
      finished: false,
      updatedAt: _now,
    ),
  };
}

/// `GET /seasons/{id}/live` through the real wiring: a member reads the
/// match in play graded on its running score, their place now and then, and
/// their duel; anyone else is refused like the leaderboard.
void main() {
  CompositionRoot root({required bool member}) {
    final competition = InMemoryCompetitionRepository();
    if (member) {
      competition.participants.add(
        Participant.fromStored(
          id: const ParticipantId(kParticipantId),
          seasonId: const SeasonId(kSeasonId),
          userId: const UserId(kUserId),
          status: ParticipantStatus.active,
          joinedAt: DateTime.utc(2026, 10),
        ),
      );
    }
    final predictions = _Predictions();
    when(
      () => predictions.listSeasonFixtures(const SeasonId(kSeasonId)),
    ).thenAnswer((_) async => const Result.ok([FixtureRef(kFixtureId)]));
    when(
      () => predictions.listByFixture(const FixtureRef(kFixtureId)),
    ).thenAnswer(
      (_) async => Result.ok([
        FixturePredictionView(
          prediction: const FixturePrediction.fromStored(
            id: PredictionId('71111111-1111-1111-1111-111111111111'),
            fixture: FixtureRef(kFixtureId),
            participantId: ParticipantId(kParticipantId),
            homeGoals: 2,
            awayGoals: 1,
          ),
          submittedAt: _now.subtract(const Duration(days: 1)),
        ),
      ]),
    );
    return CompositionRoot.forTesting(
      getLiveStanding: GetLiveStanding(
        competition: competition,
        fixturePredictions: predictions,
        totals: _Totals(),
        results: InMemoryFixtureResultRepository(),
        rulesets: _Rules(),
        duels: _Duels(),
        liveScores: _Board(),
        clock: FixedClock(_now),
      ),
    );
  }

  Future<Response> get(CompositionRoot r, {HttpMethod? method}) =>
      route.onRequest(
        wireContext(
          root: r,
          principal: userPrincipal(),
          method: method ?? HttpMethod.get,
        ),
        kSeasonId,
      );

  test('a member reads the match in play, the board and the duel', () async {
    final response = await get(root(member: true));

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    expect(body['fixtures'], [
      {
        'fixture_id': kFixtureId,
        'home_goals': 2,
        'away_goals': 1,
        'minute': 70,
        'finished': false,
        'my_points': 3,
      },
    ]);
    expect(body['duels'], [
      {
        'fixture_id': kFixtureId,
        'opponent_name': 'Rival',
        'my_points': 3,
        'opponent_points': 0,
      },
    ]);
    // Now the rival leads on 3 and the caller is not on the board; their
    // exact 2-1 would make 3 with one exact score each.
    expect(body['rank_now'], isNull);
    expect(body['points_if_ended'], 3);
    expect(body['players'], 2);
  });

  test('someone outside the season is refused (401)', () async {
    final response = await get(root(member: false));

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(
      (await decodeBody(response))['code'],
      'leaderboard.not_a_participant',
    );
  });

  test('any other method is 405', () async {
    final response = await get(root(member: true), method: HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
