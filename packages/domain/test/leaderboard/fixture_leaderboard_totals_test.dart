import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _season = SeasonId('11111111-1111-1111-1111-111111111111');
const _p1 = 'aaaaaaaa-0000-0000-0000-000000000001';
const _p2 = 'aaaaaaaa-0000-0000-0000-000000000002';
const _p3 = 'aaaaaaaa-0000-0000-0000-000000000003';
const _f1 = 'ffffffff-0000-0000-0000-000000000001';
const _f2 = 'ffffffff-0000-0000-0000-000000000002';

ParticipantFixtureScore _score(
  String fixtureId,
  String participantId,
  int points,
  FixtureScoreGrade grade,
) {
  final fixture = FixtureRef(fixtureId);
  return ParticipantFixtureScore.fromStored(
    fixture: fixture,
    participantId: ParticipantId(participantId),
    rulesetVersion: 1,
    result: FixtureScoreResult(fixture: fixture, grade: grade, points: points),
  );
}

ParticipantFixtureTotals _totals(
  String participantId,
  int points,
  int scored,
  int exact,
  int decided,
) =>
    (ParticipantFixtureTotals.of(
              participantId: ParticipantId(participantId),
              totalPoints: points,
              fixturesScored: scored,
              exactCount: exact,
              decidedCount: decided,
            )
            as Ok<ParticipantFixtureTotals>)
        .value;

void main() {
  const names = {_p1: 'one', _p2: 'two', _p3: 'three'};

  test('rankTotals produces exactly the board rank builds from rows', () {
    final fromRows = FixtureLeaderboard.rank(
      seasonId: _season,
      displayNames: names,
      previousRanks: const {_p1: 2},
      scores: [
        _score(_f1, _p1, 3, FixtureScoreGrade.exactScoreline),
        _score(_f2, _p1, 1, FixtureScoreGrade.correctOutcome),
        _score(_f1, _p2, 4, FixtureScoreGrade.exactScoreline),
        _score(_f1, _p3, 0, FixtureScoreGrade.incorrect),
        _score(_f2, _p3, 0, FixtureScoreGrade.pending),
      ],
    );
    final fromTotals = FixtureLeaderboard.rankTotals(
      seasonId: _season,
      displayNames: names,
      previousRanks: const {_p1: 2},
      totals: [
        _totals(_p3, 0, 2, 0, 1),
        _totals(_p2, 4, 1, 1, 1),
        _totals(_p1, 4, 2, 1, 2),
      ],
    );

    final rows = (fromRows as Ok<FixtureLeaderboard>).value;
    final summed = (fromTotals as Ok<FixtureLeaderboard>).value;
    expect(summed, rows);
    expect(summed.entries.map((e) => e.rank), [1, 1, 3]);
  });

  test('a participant listed twice is refused', () {
    final result = FixtureLeaderboard.rankTotals(
      seasonId: _season,
      displayNames: names,
      totals: [_totals(_p1, 1, 1, 0, 1), _totals(_p1, 2, 1, 0, 1)],
    );
    expect(result, isA<Err<FixtureLeaderboard>>());
  });

  test('impossible totals are refused', () {
    final result = ParticipantFixtureTotals.of(
      participantId: const ParticipantId(_p1),
      totalPoints: 1,
      fixturesScored: 1,
      exactCount: 1,
      decidedCount: 2,
    );
    expect(result, isA<Err<ParticipantFixtureTotals>>());
  });
}
