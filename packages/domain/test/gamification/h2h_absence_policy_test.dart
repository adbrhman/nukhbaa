/// Relegation for absence (NK183, decided 2026-10-31): three consecutive
/// counted rounds without a prediction take an elite player out of his
/// seat; the most committed extra player who played the last three rounds
/// and predicted on five days of the last thirty takes it.
library;

import 'package:domain/domain.dart';
import 'package:test/test.dart';

UserId _u(int i) =>
    UserId('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}');

H2hLeagueId _league(int i) =>
    H2hLeagueId('10000000-0000-4000-8000-${i.toString().padLeft(12, '0')}');

H2hCountedRound _round(int n, Set<UserId> present) => H2hCountedRound(
  roundId: H2hRoundId(
    '20000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  ),
  monthStart: DateTime.utc(2026, 11),
  number: n,
  day: DateTime.utc(2026, 11, n),
  present: present,
);

H2hHeldSeat _seat(int user, int league, int groupIndex, int slot) =>
    H2hHeldSeat(
      userId: _u(user),
      leagueId: _league(league),
      groupIndex: groupIndex,
      slot: slot,
    );

H2hCandidateFacts _facts(
  int user, {
  int missed = 0,
  int points = 0,
  int exact = 0,
  int days = 20,
}) => H2hCandidateFacts(
  userId: _u(user),
  missed: missed,
  points: points,
  exact: exact,
  activeDays: days,
);

bool _never(UserId _, H2hHeldSeat _) => false;

void main() {
  group('absenceRun', () {
    test('counts the trailing absences only; a presence breaks the run', () {
      final counted = [
        _round(1, {_u(1)}),
        _round(2, {_u(2)}),
        _round(3, {_u(2)}),
        _round(4, {_u(2)}),
      ];

      expect(
        [for (final r in H2hAbsencePolicy.absenceRun(_u(1), counted)) r.number],
        [2, 3, 4],
      );
      expect(H2hAbsencePolicy.absenceRun(_u(2), counted), isEmpty);
    });

    test('a round left out of the count (excused, void, no round that day) '
        'neither counts nor breaks the run', () {
      // Round 3 was excused: the caller hands in rounds 1, 2 and 4 only.
      final counted = [
        _round(1, {_u(2)}),
        _round(2, {_u(2)}),
        _round(4, {_u(2)}),
      ];

      expect(H2hAbsencePolicy.absenceRun(_u(1), counted), hasLength(3));
    });
  });

  group('rankCandidates', () {
    final counted = [
      _round(1, {_u(10), _u(11), _u(12), _u(13)}),
      _round(2, {_u(10), _u(11), _u(12)}),
      _round(3, {_u(10), _u(11), _u(12)}),
    ];

    test('fewest missed, then points, then exact, then the id', () {
      final ranked = H2hAbsencePolicy.rankCandidates(
        facts: [
          _facts(10, missed: 5, points: 90),
          _facts(11, missed: 2, points: 10, exact: 1),
          _facts(12, missed: 2, points: 10, exact: 4),
        ],
        counted: counted,
        excluded: const {},
      );

      expect([for (final f in ranked) f.userId], [_u(12), _u(11), _u(10)]);
    });

    test('five days of the last thirty, the last three rounds played, and '
        'not excluded', () {
      final ranked = H2hAbsencePolicy.rankCandidates(
        facts: [
          _facts(10, days: 4),
          _facts(11),
          _facts(12),
          // Missed round 2: not among the last three played.
          _facts(13),
        ],
        counted: counted,
        excluded: {_u(12)},
      );

      expect([for (final f in ranked) f.userId], [_u(11)]);
    });

    test('with fewer than three counted rounds, each of them', () {
      final ranked = H2hAbsencePolicy.rankCandidates(
        facts: [_facts(13), _facts(14)],
        counted: [
          _round(1, {_u(13)}),
        ],
        excluded: const {},
      );

      expect([for (final f in ranked) f.userId], [_u(13)]);
    });
  });

  group('planAbsenceMoves', () {
    // Elite seats: users 1 (group 0 slot 3), 2 (group 0 slot 1), 3 (group 1
    // slot 0). Extra seats: users 10 and 11 in group 5's league 9.
    final elite = [_seat(1, 1, 0, 3), _seat(2, 1, 0, 1), _seat(3, 2, 1, 0)];
    final extra = [_seat(10, 9, 0, 4), _seat(11, 9, 0, 7)];
    final everyoneBut12 = {_u(3), _u(10), _u(11)};
    final counted = [
      _round(1, everyoneBut12),
      _round(2, everyoneBut12),
      _round(3, everyoneBut12),
    ];

    test('users 1 and 2 missed three in a row: by seat order, each gets the '
        'best substitute left', () {
      final plan = H2hAbsencePolicy.planAbsenceMoves(
        elite: elite,
        extra: extra,
        counted: counted,
        facts: [_facts(10, missed: 3), _facts(11, missed: 1)],
        alreadyOut: const {},
        alreadyIn: const {},
        wouldRepeat: _never,
      );

      expect(plan.unfilled, isEmpty);
      expect(
        [for (final m in plan.moves) (m.out, m.substitute)],
        [(_u(2), _u(11)), (_u(1), _u(10))],
      );
      expect(plan.moves.first.extraSeat.slot, 7);
      expect(plan.moves.first.eliteSeat.slot, 1);
      expect(
        [for (final r in plan.moves.first.absentRounds) r.number],
        [1, 2, 3],
      );
    });

    test('two absences are not enough', () {
      final plan = H2hAbsencePolicy.planAbsenceMoves(
        elite: elite,
        extra: extra,
        counted: counted.sublist(1),
        facts: [_facts(10), _facts(11)],
        alreadyOut: const {},
        alreadyIn: const {},
        wouldRepeat: _never,
      );

      expect(plan.moves, isEmpty);
      expect(plan.unfilled, isEmpty);
    });

    test('a relegated player is not relegated twice and never comes back; '
        'with no substitute left the relegation waits', () {
      final plan = H2hAbsencePolicy.planAbsenceMoves(
        elite: elite,
        extra: extra,
        counted: counted,
        facts: [_facts(10), _facts(11)],
        alreadyOut: {_u(1), _u(11)},
        alreadyIn: {_u(10)},
        wouldRepeat: _never,
      );

      expect(plan.moves, isEmpty);
      expect([for (final u in plan.unfilled) u.out], [_u(2)]);
    });

    test('a substitute whose seat would make the relegated player meet an '
        'old opponent again is passed over', () {
      final plan = H2hAbsencePolicy.planAbsenceMoves(
        elite: [elite[1]],
        extra: extra,
        counted: counted,
        facts: [_facts(10, missed: 3), _facts(11, missed: 1)],
        alreadyOut: const {},
        alreadyIn: const {},
        wouldRepeat: (out, seat) => seat.slot == 7,
      );

      expect(plan.moves.single.substitute, _u(10));
    });
  });

  group('table with seat swaps', () {
    test('the seat\'s new holder plays its rounds from the swap on; the '
        'average is over the round\'s holders', () {
      final joined = DateTime.utc(2026, 11);
      // Slots 0 and 1 of a two-seat group. User 1 leaves slot 0 after
      // round 1; user 3 holds it from round 2.
      final members = [
        H2hMember(userId: _u(1), slot: 0, joinedAt: joined, untilRound: 1),
        H2hMember(userId: _u(2), slot: 1, joinedAt: joined),
        H2hMember(userId: _u(3), slot: 0, joinedAt: joined, fromRound: 2),
      ];
      final rounds = [
        H2hRoundRef(number: 1, day: DateTime.utc(2026, 11, 1)),
        H2hRoundRef(number: 2, day: DateTime.utc(2026, 11, 2)),
      ];
      H2hRoundScore score(int user, int round, int points) => H2hRoundScore(
        userId: _u(user),
        round: round,
        points: points,
        exactCount: 0,
        predictedCount: 2,
      );

      final table = H2hLeaguePolicy.table(
        capacity: 2,
        members: members,
        rounds: rounds,
        scores: [
          score(1, 1, 5),
          score(2, 1, 3),
          score(2, 2, 4),
          score(3, 2, 6),
        ],
      );
      final byUser = {for (final s in table) s.userId: s};

      expect(table, hasLength(3));
      expect(byUser[_u(1)]!.played, 1);
      expect(byUser[_u(1)]!.won, 1);
      expect(byUser[_u(3)]!.played, 1);
      expect(byUser[_u(3)]!.won, 1);
      expect(byUser[_u(3)]!.matches.single.opponentId, _u(2));
      expect(byUser[_u(2)]!.played, 2);
      expect(byUser[_u(2)]!.lost, 2);
      expect(
        [for (final m in byUser[_u(2)]!.matches) m.opponentId],
        [_u(1), _u(3)],
      );
    });

    test('mergeStandings adds the parts of a player\'s month and reads him '
        'at his current seat', () {
      final joined = DateTime.utc(2026, 11);
      final rounds = [
        H2hRoundRef(number: 1, day: DateTime.utc(2026, 11, 1)),
        H2hRoundRef(number: 2, day: DateTime.utc(2026, 11, 2)),
      ];
      H2hRoundScore score(int user, int round, int points) => H2hRoundScore(
        userId: _u(user),
        round: round,
        points: points,
        exactCount: 1,
        predictedCount: 2,
      );
      final scores = [
        score(1, 1, 5),
        score(2, 1, 3),
        score(1, 2, 2),
        score(4, 2, 1),
      ];
      // User 1 plays round 1 in group A (slot 0) and round 2 in group B
      // (slot 1).
      final partA = H2hLeaguePolicy.table(
        capacity: 2,
        members: [
          H2hMember(userId: _u(1), slot: 0, joinedAt: joined, untilRound: 1),
          H2hMember(userId: _u(2), slot: 1, joinedAt: joined),
        ],
        rounds: rounds,
        scores: scores,
      ).firstWhere((s) => s.userId == _u(1));
      final seatB = H2hMember(
        userId: _u(1),
        slot: 1,
        joinedAt: DateTime.utc(2026, 11, 2),
        fromRound: 2,
      );
      final partB = H2hLeaguePolicy.table(
        capacity: 2,
        members: [
          H2hMember(userId: _u(4), slot: 0, joinedAt: joined),
          seatB,
        ],
        rounds: rounds,
        scores: scores,
      ).firstWhere((s) => s.userId == _u(1));

      final merged = H2hLeaguePolicy.mergeStandings(
        parts: [partB, partA],
        seat: seatB,
      );

      expect(merged.played, 2);
      expect(merged.won, 2);
      expect(merged.leaguePoints, 6);
      expect(merged.pointsFor, 7);
      expect(merged.exactCount, 2);
      expect(merged.slot, 1);
      expect([for (final m in merged.matches) m.round], [1, 2]);
    });
  });
}
