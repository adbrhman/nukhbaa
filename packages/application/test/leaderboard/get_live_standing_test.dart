import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart'
    show FakeRulesetProvider, FixedClock, userPrincipal;
import '../prediction/fake_fixture_prediction_repository.dart';
import '../scoring/fakes.dart'
    show FakeFixtureResultRepository, scoringParticipant;

const _season = '11111111-1111-1111-1111-111111111111';
const _live = '21111111-1111-1111-1111-111111111111';
const _later = '22222222-1111-1111-1111-111111111111';
const _meUser = '31111111-1111-1111-1111-111111111111';
const _outsider = '32222222-1111-1111-1111-111111111111';
const _me = '41111111-1111-1111-1111-111111111111';
const _rival = '42222222-1111-1111-1111-111111111111';
const _leader = '43333333-1111-1111-1111-111111111111';

final DateTime _now = DateTime.utc(2026, 10, 6, 19);

/// The rules shipped today: only the exact score earns, three points,
/// doubled by the double.
final RulesetSnapshot _rules =
    (RulesetSnapshot.create(
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
            )
            as Ok<RulesetSnapshot>)
        .value;

final class _Board implements LiveScoreBoard {
  _Board(this.scores);

  final Map<String, LiveScore> scores;

  @override
  void put(Map<String, LiveScore> scores) => this.scores.addAll(scores);

  @override
  void remove(Iterable<String> fixtureIds) =>
      scores.removeWhere((id, _) => fixtureIds.contains(id));

  @override
  Map<String, LiveScore> read(Iterable<String> fixtureIds) =>
      <String, LiveScore>{
        for (final String id in fixtureIds)
          if (scores[id] case final LiveScore s) id: s,
      };
}

final class _Totals implements FixtureTotalsReader {
  final List<ParticipantFixtureTotals> lines = [];
  int reads = 0;

  void add(String participant, {required int points, required int exact}) {
    lines.add(
      (ParticipantFixtureTotals.of(
                participantId: ParticipantId(participant),
                totalPoints: points,
                fixturesScored: exact + 1,
                exactCount: exact,
                decidedCount: exact,
              )
              as Ok<ParticipantFixtureTotals>)
          .value,
    );
  }

  @override
  Future<Result<List<ParticipantFixtureTotals>>> totalsFor(
    List<FixtureRef> fixtures,
  ) async {
    reads++;
    return Result.ok(lines);
  }
}

final class _Duels implements DuelReader {
  _Duels(this.duels);

  final List<DuelRecord> duels;

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
  }) async => Result.ok(duels);
}

DuelRecord _duel(String fixture, DuelPick mine, DuelPick theirs) => DuelRecord(
  duelId: const DuelId('51111111-1111-1111-1111-111111111111'),
  challengeId: const DuelChallengeId('52222222-1111-1111-1111-111111111111'),
  fixture: FixtureRef(fixture),
  homeTeam: 'Home',
  awayTeam: 'Away',
  kickoffAt: _now.subtract(const Duration(hours: 1)),
  acceptedAt: _now.subtract(const Duration(hours: 3)),
  callerIsChallenger: true,
  opponentUserId: const UserId('61111111-1111-1111-1111-111111111111'),
  opponentName: 'Rival',
  myPick: mine,
  opponentPick: theirs,
  myScore: null,
  opponentScore: null,
);

LiveScore _score(int home, int away) => LiveScore(
  homeGoals: home,
  awayGoals: away,
  minute: 63,
  finished: false,
  updatedAt: _now,
);

typedef _Harness = ({
  GetLiveStanding useCase,
  _Totals totals,
  FakeFixtureResultRepository results,
  _Board board,
});

_Harness _harness({LiveScoreBoard? board, List<DuelRecord> duels = const []}) {
  final competition = FakeCompetitionRepository()
    ..seedParticipant(
      scoringParticipant(id: _me, seasonId: _season, userId: _meUser),
    );
  final predictions = FakeFixturePredictionRepository();
  for (final (int order, String fixture) in [(1, _live), (2, _later)]) {
    predictions.seedSeasonFixture(
      SeasonFixture.fromStored(
        seasonId: const SeasonId(_season),
        fixture: FixtureRef(fixture),
        displayOrder: order,
      ),
    );
  }
  void predict(
    String id,
    String participant,
    int home,
    int away, {
    bool isDouble = false,
  }) {
    predictions.seedPrediction(
      FixturePrediction.fromStored(
        id: PredictionId(id),
        fixture: const FixtureRef(_live),
        participantId: ParticipantId(participant),
        homeGoals: home,
        awayGoals: away,
        isDouble: isDouble,
      ),
      _now.subtract(const Duration(days: 1)),
    );
  }

  // The live match stands 1-0: the viewer's 1-0 double is exact (6), the
  // rival's 2-1 earns nothing.
  predict('71111111-1111-1111-1111-111111111111', _me, 1, 0, isDouble: true);
  predict('72222222-1111-1111-1111-111111111111', _rival, 2, 1);
  final totals = _Totals()
    ..add(_leader, points: 8, exact: 2)
    ..add(_rival, points: 6, exact: 2)
    ..add(_me, points: 3, exact: 1);
  final results = FakeFixtureResultRepository();
  final _Board live = board is _Board ? board : _Board({_live: _score(1, 0)});
  return (
    useCase: GetLiveStanding(
      competition: competition,
      fixturePredictions: predictions,
      totals: totals,
      results: results,
      rulesets: FakeRulesetProvider(Result.ok(_rules)),
      duels: _Duels(duels),
      liveScores: board == null ? null : live,
      clock: FixedClock(_now),
    ),
    totals: totals,
    results: results,
    board: live,
  );
}

Future<LiveStanding> _read(_Harness h) async {
  final result = await h.useCase(
    principal: userPrincipal(_meUser),
    seasonId: _season,
  );
  return (result as Ok<LiveStanding>).value;
}

void main() {
  test(
    'a match in play is graded on its running score, the double too',
    () async {
      final h = _harness(board: _Board({_live: _score(1, 0)}));

      final LiveStanding standing = await _read(h);

      expect(standing.fixtures, hasLength(1));
      final LiveFixtureStanding line = standing.fixtures.single;
      expect(line.fixture.value, _live);
      expect((line.homeGoals, line.awayGoals, line.minute), (1, 0, 63));
      expect(line.myPoints, 6);
    },
  );

  test('the month place now and if the match ended now', () async {
    final h = _harness(board: _Board({_live: _score(1, 0)}));

    final LiveStanding standing = await _read(h);

    // Now: leader 8, rival 6, viewer 3. Then the viewer's exact double
    // makes 9, past the leader's 8.
    expect((standing.rankNow, standing.pointsNow), (3, 3));
    expect((standing.rankIfEnded, standing.pointsIfEnded), (1, 9));
    expect(standing.players, 3);
  });

  test('a duel on the match says who leads', () async {
    final h = _harness(
      board: _Board({_live: _score(1, 0)}),
      duels: [
        _duel(
          _live,
          const DuelPick(homeGoals: 1, awayGoals: 0, isDouble: false),
          const DuelPick(homeGoals: 0, awayGoals: 0, isDouble: false),
        ),
        _duel(
          _later,
          const DuelPick(homeGoals: 1, awayGoals: 0, isDouble: false),
          const DuelPick(homeGoals: 0, awayGoals: 0, isDouble: false),
        ),
      ],
    );

    final LiveStanding standing = await _read(h);

    expect(standing.duels, hasLength(1));
    final LiveDuelStanding duel = standing.duels.single;
    expect(duel.opponentName, 'Rival');
    expect((duel.myPoints, duel.opponentPoints), (3, 0));
  });

  test('a recorded result is left to the board, never counted twice', () async {
    final h = _harness(board: _Board({_live: _score(1, 0)}));
    h.results.seed(
      (FixtureResult.create(
                fixture: const FixtureRef(_live),
                homeGoals: 1,
                awayGoals: 0,
              )
              as Ok<FixtureResult>)
          .value,
    );

    final LiveStanding standing = await _read(h);

    expect(standing.fixtures, isEmpty);
    expect(h.totals.reads, 0);
  });

  test('nothing in play reads nothing else', () async {
    final h = _harness(board: _Board({}));

    final LiveStanding standing = await _read(h);

    expect(standing.fixtures, isEmpty);
    expect(standing.rankNow, isNull);
    expect(h.totals.reads, 0);
  });

  test('without running scores nothing is ever in play', () async {
    final h = _harness();

    final LiveStanding standing = await _read(h);

    expect(standing.fixtures, isEmpty);
  });

  test('someone outside the season is refused', () async {
    final h = _harness(board: _Board({_live: _score(1, 0)}));

    final result = await h.useCase(
      principal: userPrincipal(_outsider),
      seasonId: _season,
    );

    expect(
      (result as Err<LiveStanding>).error.code,
      'leaderboard.not_a_participant',
    );
  });
}
