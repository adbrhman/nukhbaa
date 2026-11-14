/// NK278 (owner, 2026-11-14; migration 0214): absence in every group from
/// December 2026, the last group's vacant seat, and November as before.
library;

import 'package:domain/domain.dart';
import 'package:test/test.dart';

UserId _u(int n) => UserId('u$n');

const _g1 = H2hLeagueId('11111111-1111-4111-8111-000000000001');
const _g5 = H2hLeagueId('11111111-1111-4111-8111-000000000005');
const _g6 = H2hLeagueId('11111111-1111-4111-8111-000000000006');
const _g7 = H2hLeagueId('11111111-1111-4111-8111-000000000007');

final _december = DateTime.utc(2026, 12);

H2hHeldSeat _seat(int user, H2hLeagueId league, int index, int slot) =>
    H2hHeldSeat(
      userId: _u(user),
      leagueId: league,
      groupIndex: index,
      slot: slot,
    );

H2hCountedRound _round(int n, Set<int> present, {DateTime? month}) =>
    H2hCountedRound(
      roundId: H2hRoundId(
        '22222222-2222-4222-8222-${n.toString().padLeft(12, '0')}',
      ),
      monthStart: month ?? _december,
      number: n,
      day: DateTime.utc(2026, 12, n),
      present: {for (final p in present) _u(p)},
    );

H2hCandidateFacts _facts(
  int user, {
  int predicted = 10,
  int points = 0,
  int exact = 0,
  int outcomes = 0,
  int activeDays = 20,
}) => H2hCandidateFacts(
  userId: _u(user),
  missed: 0,
  points: points,
  exact: exact,
  activeDays: activeDays,
  predicted: predicted,
  outcomes: outcomes,
);

void main() {
  test('a group goes down to the next one; the elite groups to 5', () {
    for (final (from, to) in [
      (1, 5),
      (2, 5),
      (4, 5),
      (5, 6),
      (6, 7),
      (9, 10),
    ]) {
      expect(H2hAbsencePolicy.groupBelow(from), to, reason: '$from');
    }
  });

  test('a seat taken after round 1 counts no round before it', () {
    // Absent in rounds 1 to 7; the seat was taken from round 8.
    final counted = [
      for (var n = 1; n <= 9; n++) _round(n, n >= 8 ? {1} : const <int>{}),
    ];
    final lateSeat = H2hHeldSeat(
      userId: _u(1),
      leagueId: _g7,
      groupIndex: 2,
      slot: 0,
      fromRound: 8,
    );
    expect(
      H2hAbsencePolicy.absenceRunIn(lateSeat, counted, _december),
      isEmpty,
    );
    final drawn = H2hHeldSeat(
      userId: _u(2),
      leagueId: _g1,
      groupIndex: 0,
      slot: 0,
    );
    expect(
      H2hAbsencePolicy.absenceRunIn(drawn, counted, _december),
      hasLength(9),
    );
    // Absent from round 8 on: three rounds, he goes down.
    final away = [
      for (var n = 1; n <= 10; n++) _round(n, n < 8 ? {1} : const <int>{}),
    ];
    expect(
      H2hAbsencePolicy.absenceRunIn(lateSeat, away, _december),
      hasLength(3),
    );
  });

  group('planDecemberMoves', () {
    // المجموعة 1: 10..13; 5: 50..53; 6: 60..63, the last that plays; the
    // waiting list holds 70 and 71. 10, 50, 60 and 61 missed three rounds.
    final groups = [
      H2hAbsenceGroup(
        leagueId: _g1,
        number: 1,
        seats: [for (var s = 0; s < 4; s++) _seat(10 + s, _g1, 0, s)],
      ),
      H2hAbsenceGroup(
        leagueId: _g5,
        number: 5,
        seats: [for (var s = 0; s < 4; s++) _seat(50 + s, _g5, 0, s)],
      ),
      H2hAbsenceGroup(
        leagueId: _g6,
        number: 6,
        seats: [for (var s = 0; s < 4; s++) _seat(60 + s, _g6, 1, s)],
      ),
    ];
    final waiting = [_seat(70, _g7, 2, 0), _seat(71, _g7, 2, 1)];
    final everyone = {
      for (var s = 0; s < 4; s++) ...{10 + s, 50 + s, 60 + s},
      70,
      71,
    };
    final absent = {10, 50, 60, 61};
    final counted = [
      for (var n = 1; n <= 3; n++) _round(n, everyone.difference(absent)),
    ];
    final facts = [
      _facts(51, predicted: 30),
      _facts(52, predicted: 20, points: 99),
      _facts(53, predicted: 10),
      _facts(62, predicted: 30),
      _facts(63, predicted: 25),
      _facts(70, predicted: 30),
      _facts(71, predicted: 40, activeDays: 4),
    ];

    H2hDecemberPlan plan({
      List<H2hCandidateFacts>? withFacts,
      List<H2hOpenVacancy> open = const [],
      Set<UserId> alreadyOut = const {},
      Set<UserId> alreadyIn = const {},
      bool Function(UserId, H2hHeldSeat)? wouldRepeat,
    }) => H2hAbsencePolicy.planDecemberMoves(
      groups: groups,
      waiting: waiting,
      open: open,
      counted: counted,
      facts: withFacts ?? facts,
      monthStart: _december,
      alreadyOut: alreadyOut,
      alreadyIn: alreadyIn,
      wouldRepeat: wouldRepeat ?? ((_, _) => false),
    );

    test('each group sends its absent player one group down', () {
      final p = plan();
      expect(
        [
          for (final m in p.moves)
            (m.out, m.eliteSeat.leagueId, m.substitute, m.extraSeat.leagueId),
        ],
        [(_u(10), _g1, _u(51), _g5), (_u(50), _g5, _u(62), _g6)],
      );
      expect(p.moves.first.extraSeat.slot, 1);
      expect(p.moves.first.absentRounds, hasLength(3));
      expect(p.unfilled, isEmpty);
    });

    test('the last group: one seat filled at once from the waiting list, '
        'one left vacant', () {
      final p = plan();
      expect(p.vacancies.map((v) => v.out).toList(), [_u(60), _u(61)]);
      expect(p.vacancies.first.seat.slot, 0);
      expect(p.vacancies.first.fill!.user, _u(70));
      expect(p.vacancies.first.fill!.waitingSeat.slot, 0);
      // 71 predicted on four days only: no fill.
      expect(p.vacancies.last.fill, isNull);
      expect(p.fills, isEmpty);
    });

    test('the most committed comes up: fewer absences, then predictions, '
        'before points', () {
      // 52 scored the most but predicted less than 51.
      expect(plan().moves.first.substitute, _u(51));
      // 51 missed a round of the month: 52 comes up instead.
      final withAbsence = H2hAbsencePolicy.rankCommitted(
        facts: [_facts(51, predicted: 30), _facts(52, predicted: 20)],
        counted: [
          ...counted,
          _round(4, everyone.difference({...absent, 51})),
          _round(5, everyone.difference(absent)),
          _round(6, everyone.difference(absent)),
          _round(7, everyone.difference(absent)),
        ],
        monthStart: _december,
        excluded: const {},
      );
      expect(withAbsence.map((f) => f.userId).toList(), [_u(52), _u(51)]);
      // Equal on absences and predictions: exact, then outcomes, points.
      final tie = H2hAbsencePolicy.rankCommitted(
        facts: [
          _facts(1, exact: 1, outcomes: 0, points: 0),
          _facts(2, exact: 1, outcomes: 3, points: 0),
          _facts(3, exact: 2, outcomes: 0, points: 0),
        ],
        counted: const [],
        monthStart: _december,
        excluded: const {},
      );
      expect(tie.map((f) => f.userId).toList(), [_u(3), _u(2), _u(1)]);
    });

    test('no qualifying player below: he stays, tried again next round', () {
      final p = plan(
        withFacts: [
          for (final f in facts)
            if (f.userId != _u(62) && f.userId != _u(63)) f,
        ],
      );
      expect(p.unfilled.map((u) => u.out).toList(), [_u(50)]);
      expect(p.moves.map((m) => m.out).toList(), [_u(10)]);
    });

    test('a seat left vacant before is filled first, the oldest first', () {
      const open = H2hOpenVacancy(
        id: 'v1',
        leagueId: _g6,
        slot: 3,
        outUser: UserId('u99'),
      );
      final p = plan(open: [open]);
      expect(p.fills.single.$1.id, 'v1');
      expect(p.fills.single.$2.user, _u(70));
      // 70 is taken: today's vacancies stay vacant.
      expect(p.vacancies.every((v) => v.fill == null), isTrue);
    });

    test('nobody moves twice: who went down or came up this month is left '
        'alone, and never comes back up', () {
      final p = plan(alreadyOut: {_u(10), _u(70)}, alreadyIn: {_u(51)});
      expect(p.moves.map((m) => m.out), isNot(contains(_u(10))));
      expect(p.moves.map((m) => m.substitute), isNot(contains(_u(51))));
      expect(p.vacancies.every((v) => v.fill == null), isTrue);
      final users = [
        for (final m in p.moves) ...[m.out, m.substitute],
        for (final v in p.vacancies) ...[v.out, ?v.fill?.user],
        for (final f in p.fills) f.$2.user,
      ];
      expect(users.toSet(), hasLength(users.length));
      // The whole plan once more, as a second run reads it: nothing new.
      final first = plan();
      final again = plan(
        alreadyOut: {
          for (final m in first.moves) m.out,
          for (final v in first.vacancies) v.out,
        },
        alreadyIn: {
          for (final m in first.moves) m.substitute,
          for (final v in first.vacancies) ?v.fill?.user,
        },
      );
      expect(again.moves, isEmpty);
      expect(again.vacancies, isEmpty);
      expect(again.fills, isEmpty);
    });

    test('a substitute whose seat repeats a match is passed over', () {
      final p = plan(
        wouldRepeat: (out, seat) => out == _u(10) && seat.userId == _u(51),
      );
      expect(p.moves.first.substitute, _u(52));
    });

    test('the last group that plays may be an elite group', () {
      final p = H2hAbsencePolicy.planDecemberMoves(
        groups: [groups.first],
        waiting: waiting,
        open: const [],
        counted: counted,
        facts: facts,
        monthStart: _december,
        alreadyOut: const {},
        alreadyIn: const {},
        wouldRepeat: (_, _) => false,
      );
      expect(p.moves, isEmpty);
      expect(p.vacancies.single.out, _u(10));
      expect(p.vacancies.single.fill!.user, _u(70));
    });
  });

  group('a vacant seat in the table', () {
    H2hMember member(String id, int slot, {int from = 1, int? until}) =>
        H2hMember(
          userId: UserId(id),
          slot: slot,
          joinedAt: DateTime.utc(2026, 11, 1, 3, slot),
          fromRound: from,
          untilRound: until,
        );
    H2hRoundScore score(String id, int round, int points) => H2hRoundScore(
      userId: UserId(id),
      round: round,
      points: points,
      exactCount: 0,
      predictedCount: 3,
    );

    test('from December an empty seat is an absent opponent, not the '
        'average', () {
      H2hMatch aOf(int points) => H2hLeaguePolicy.table(
        capacity: 4,
        members: [member('a', 0), member('b', 1)],
        rounds: [H2hRoundRef(number: 1, day: DateTime.utc(2026, 12, 3))],
        scores: [score('a', 1, points), score('b', 1, 9)],
      ).firstWhere((s) => s.userId == const UserId('a')).matches.single;

      expect(aOf(1).opponentId, isNull);
      expect(aOf(1).opponentPresent, isFalse);
      expect(aOf(1).opponentPoints, 0);
      // Below the group's average of 5, a win all the same.
      expect(aOf(1).result, H2hMatchResult.win);
      // No correct prediction: one point.
      expect(aOf(0).result, H2hMatchResult.draw);
    });

    test('November keeps the group average', () {
      final a = H2hLeaguePolicy.table(
        capacity: 4,
        members: [member('a', 0), member('b', 1)],
        rounds: [H2hRoundRef(number: 1, day: DateTime.utc(2026, 11, 3))],
        scores: [score('a', 1, 1), score('b', 1, 9)],
      ).firstWhere((s) => s.userId == const UserId('a')).matches.single;
      expect(a.opponentPoints, 5);
      expect(a.result, H2hMatchResult.loss);
    });

    test('from December the seat\'s record passes on across the vacant '
        'rounds; in November it never had to', () {
      H2hStanding standing(String id, int won) => H2hStanding(
        userId: UserId(id),
        slot: 0,
        joinedAt: DateTime.utc(2026, 11),
        won: won,
        drawn: 0,
        lost: 0,
        pointsFor: 0,
        exactCount: 0,
        presentRounds: 0,
        matches: const <H2hMatch>[],
      );
      final members = [member('a', 0, until: 5), member('b', 0, from: 8)];
      final table = [standing('a', 2), standing('b', 1)];

      final december = H2hLeaguePolicy.seatRecords(
        members: members,
        table: table,
        day: DateTime.utc(2026, 12, 9),
      );
      expect(december.given[const UserId('a')]!.single.won, 2);
      expect(december.taken[const UserId('b')]!.single.won, 2);
      expect(december.kept.containsKey(const UserId('a')), isFalse);

      final november = H2hLeaguePolicy.seatRecords(
        members: members,
        table: table,
        day: DateTime.utc(2026, 11, 9),
      );
      expect(november.kept[const UserId('a')]!.single.won, 2);
      expect(november.given, isEmpty);
    });
  });
}
