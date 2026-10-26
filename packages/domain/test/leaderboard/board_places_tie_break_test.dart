// Batch 129 (decided 2026-10-14): three players on 45 points all showed
// tenth. After points and exact scorelines, a tie now goes to the right
// outcomes, then to the earlier join of the contest, so every player gets a
// place of his own. Players share a place only when level on all four (the
// month's invitation points left the chain on 2026-10-26). The same chain ranks the daily snapshot
// (supabase/tests/0108_board_places_tie_break_test.sql) and the season.
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _season = SeasonId('11111111-1111-1111-1111-111111111111');
const _a = 'aaaaaaaa-0000-0000-0000-000000000001';
const _b = 'aaaaaaaa-0000-0000-0000-000000000002';
const _c = 'aaaaaaaa-0000-0000-0000-000000000003';
const _d = 'aaaaaaaa-0000-0000-0000-000000000004';

ParticipantFixtureTotals _line(
  String id, {
  int points = 45,
  int exact = 14,
  int outcome = 0,
  DateTime? joinedAt,
}) =>
    (ParticipantFixtureTotals.of(
              participantId: ParticipantId(id),
              totalPoints: points,
              fixturesScored: 115,
              exactCount: exact,
              decidedCount: 110,
              outcomeCount: outcome,
              joinedAt: joinedAt,
            )
            as Ok<ParticipantFixtureTotals>)
        .value;

List<(String, int)> _places(List<ParticipantFixtureTotals> totals) {
  final board =
      (FixtureLeaderboard.rankTotals(
                seasonId: _season,
                totals: totals,
                displayNames: const {},
              )
              as Ok<FixtureLeaderboard>)
          .value;
  return [
    for (final FixtureLeaderboardEntry e in board.entries)
      (e.participantId.value, e.rank),
  ];
}

void main() {
  final DateTime day1 = DateTime.utc(2026, 10, 1, 6);
  final DateTime day2 = DateTime.utc(2026, 10, 2, 6);
  final DateTime day3 = DateTime.utc(2026, 10, 3, 6);

  test('three players on 45 points get three places, not one', () {
    expect(
      _places([
        _line(_a, outcome: 30, joinedAt: day1),
        _line(_b, outcome: 32, joinedAt: day2),
        _line(_c, outcome: 32, joinedAt: day3),
      ]),
      [(_b, 1), (_c, 2), (_a, 3)],
    );
  });

  test('more right outcomes rank higher, whoever joined first', () {
    expect(
      _places([
        _line(_a, outcome: 5, joinedAt: day1),
        _line(_b, outcome: 6, joinedAt: day3),
      ]),
      [(_b, 1), (_a, 2)],
    );
  });

  test('level on outcomes: the earlier joiner ranks higher', () {
    expect(
      _places([
        _line(_a, outcome: 5, joinedAt: day2),
        _line(_b, outcome: 5, joinedAt: day1),
      ]),
      [(_b, 1), (_a, 2)],
    );
  });

  test('the earlier tie-breaks still come first', () {
    expect(
      _places([
        _line(_a, outcome: 40, joinedAt: day1),
        _line(_b, exact: 15, points: 45, outcome: 0, joinedAt: day3),
        _line(_c, outcome: 0, joinedAt: day3),
        _line(_d, points: 48, joinedAt: day3),
      ]),
      [(_d, 1), (_b, 2), (_a, 3), (_c, 4)],
    );
  });

  test('a player whose join time is unknown goes after a known one', () {
    expect(
      _places([_line(_a, outcome: 5), _line(_b, outcome: 5, joinedAt: day3)]),
      [(_b, 1), (_a, 2)],
    );
  });

  test('level on all four: the same place, the next one skipped', () {
    expect(
      _places([
        _line(_a, outcome: 5, joinedAt: day1),
        _line(_b, outcome: 5, joinedAt: day1),
        _line(_c, outcome: 4, joinedAt: day1),
      ]),
      [(_a, 1), (_b, 1), (_c, 3)],
    );
  });

  test('a board built from score rows counts the right outcomes', () {
    ParticipantFixtureScore score(
      String fixture,
      String id,
      int points,
      FixtureScoreGrade grade,
    ) {
      final ref = FixtureRef(fixture);
      return ParticipantFixtureScore.fromStored(
        fixture: ref,
        participantId: ParticipantId(id),
        rulesetVersion: 1,
        result: FixtureScoreResult(fixture: ref, grade: grade, points: points),
      );
    }

    const f1 = 'ffffffff-0000-0000-0000-000000000001';
    const f2 = 'ffffffff-0000-0000-0000-000000000002';
    final board =
        (FixtureLeaderboard.rank(
                  seasonId: _season,
                  displayNames: const {},
                  scores: [
                    score(f1, _a, 3, FixtureScoreGrade.exactScoreline),
                    score(f2, _a, 0, FixtureScoreGrade.incorrect),
                    score(f1, _b, 3, FixtureScoreGrade.exactScoreline),
                    score(f2, _b, 0, FixtureScoreGrade.correctOutcome),
                  ],
                )
                as Ok<FixtureLeaderboard>)
            .value;
    expect(
      [for (final e in board.entries) (e.participantId.value, e.rank)],
      [(_b, 1), (_a, 2)],
    );
    expect(board.entries.first.outcomeCount, 1);
  });

  test('the season board breaks ties the same way', () {
    SportingSeasonStanding standing(String id, int outcome, DateTime joined) =>
        (SportingSeasonStanding.projected(
                  userId: UserId(id),
                  displayName: id,
                  totalPoints: 90,
                  fixturesScored: 200,
                  exactCount: 28,
                  decidedCount: 190,
                  monthsPlayed: 2,
                  outcomeCount: outcome,
                  joinedAt: joined,
                )
                as Ok<SportingSeasonStanding>)
            .value;

    final board =
        (SportingSeasonLeaderboard.rank(
                  season: SportingSeason.containing(DateTime.utc(2026, 10, 14)),
                  standings: [
                    standing(_a, 50, day1),
                    standing(_b, 60, day3),
                    standing(_c, 60, day2),
                  ],
                )
                as Ok<SportingSeasonLeaderboard>)
            .value;
    expect(
      [for (final e in board.entries) (e.userId.value, e.rank)],
      [(_c, 1), (_b, 2), (_a, 3)],
    );
  });
}
