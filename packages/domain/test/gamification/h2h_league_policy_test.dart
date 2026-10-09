import 'package:domain/domain.dart';
import 'package:test/test.dart';

H2hMember _member(String id, int slot) => H2hMember(
  userId: UserId(id),
  slot: slot,
  joinedAt: DateTime.utc(2026, 11, 1, 3, slot),
);

H2hRoundRef _round(int number, int day) =>
    H2hRoundRef(number: number, day: DateTime.utc(2026, 11, day));

H2hRoundScore _score(
  String id,
  int round, {
  int points = 0,
  int exact = 0,
  int predicted = 1,
}) => H2hRoundScore(
  userId: UserId(id),
  round: round,
  points: points,
  exactCount: exact,
  predictedCount: predicted,
);

H2hMatch _match(String opponent, H2hMatchResult result) => H2hMatch(
  round: 1,
  day: DateTime.utc(2026, 11, 3),
  opponentId: UserId(opponent),
  points: 0,
  opponentPoints: 0,
  present: true,
  opponentPresent: true,
  result: result,
);

H2hStanding _standing(
  String id, {
  int won = 0,
  int drawn = 0,
  int lost = 0,
  int pointsFor = 0,
  int exact = 0,
  int seatMinute = 0,
  List<H2hMatch> matches = const <H2hMatch>[],
}) => H2hStanding(
  userId: UserId(id),
  slot: 0,
  joinedAt: DateTime.utc(2026, 11, 1).add(Duration(minutes: seatMinute)),
  won: won,
  drawn: drawn,
  lost: lost,
  pointsFor: pointsFor,
  exactCount: exact,
  presentRounds: 1,
  matches: matches,
);

/// A group of [size] members named `<prefix>01`, `<prefix>02`, ... already in
/// their final order.
H2hGroupResult _group(H2hDivision division, String prefix, int size) =>
    H2hGroupResult(
      division: division,
      placings: [
        for (var rank = 1; rank <= size; rank++)
          H2hPlacing(
            rank: rank,
            standing: _standing(
              '$prefix${rank.toString().padLeft(2, '0')}',
              won: 100 - rank,
            ),
          ),
      ],
    );

List<H2hGroupResult> _standardMonth() => [
  _group(H2hDivision.first, 'a', 20),
  _group(H2hDivision.second, 'b', 20),
  _group(H2hDivision.third, 'c', 20),
  _group(H2hDivision.fourth, 'd', 10),
];

Set<UserId> _everyone(
  List<H2hGroupResult> groups, {
  Set<String> except = const <String>{},
}) => {
  for (final group in groups)
    for (final placing in group.placings)
      if (!except.contains(placing.standing.userId.value))
        placing.standing.userId,
};

Map<String, H2hFinish> _byUser(List<H2hFinish> finishes) => {
  for (final finish in finishes) finish.placing.standing.userId.value: finish,
};

int _countIn(List<H2hFinish> finishes, H2hDivision? division) =>
    finishes.where((f) => f.nextDivision == division).length;

void main() {
  group('H2hLeaguePolicy months', () {
    test('a month opens on its first day', () {
      expect(
        H2hLeaguePolicy.monthStartOf(DateTime.utc(2026, 11, 17)),
        DateTime.utc(2026, 11),
      );
    });

    test('the month end is the next first day, across a year', () {
      expect(
        H2hLeaguePolicy.monthEndOf(DateTime.utc(2026, 12, 5)),
        DateTime.utc(2027),
      );
    });

    test('the previous month crosses a year backwards', () {
      expect(
        H2hLeaguePolicy.previousMonthOf(DateTime.utc(2027, 1, 1)),
        DateTime.utc(2026, 12),
      );
    });

    test('the league opens to everyone in November 2026', () {
      expect(H2hLeaguePolicy.firstMonth, DateTime.utc(2026, 11));
    });
  });

  group('H2hLeaguePolicy rounds', () {
    test('six fixtures make a regular round, five a fill round', () {
      expect(H2hLeaguePolicy.roundKindOf(21), H2hRoundKind.regular);
      expect(H2hLeaguePolicy.roundKindOf(6), H2hRoundKind.regular);
      expect(H2hLeaguePolicy.roundKindOf(5), H2hRoundKind.fill);
      expect(H2hLeaguePolicy.roundKindOf(4), isNull);
      expect(H2hLeaguePolicy.roundKindOf(0), isNull);
    });

    test('the system approves regular days; a fill day needs an admin', () {
      expect(
        H2hLeaguePolicy.canApprove(
          fixtureCount: 6,
          approvedRounds: 0,
          byAdmin: false,
        ),
        isTrue,
      );
      expect(
        H2hLeaguePolicy.canApprove(
          fixtureCount: 5,
          approvedRounds: 3,
          byAdmin: false,
        ),
        isFalse,
      );
      expect(
        H2hLeaguePolicy.canApprove(
          fixtureCount: 5,
          approvedRounds: 3,
          byAdmin: true,
        ),
        isTrue,
      );
      expect(
        H2hLeaguePolicy.canApprove(
          fixtureCount: 4,
          approvedRounds: 0,
          byAdmin: true,
        ),
        isFalse,
      );
    });

    test('a month holds at most 19 rounds', () {
      expect(
        H2hLeaguePolicy.canApprove(
          fixtureCount: 12,
          approvedRounds: 18,
          byAdmin: false,
        ),
        isTrue,
      );
      expect(
        H2hLeaguePolicy.canApprove(
          fixtureCount: 12,
          approvedRounds: 19,
          byAdmin: true,
        ),
        isFalse,
      );
    });

    test('five days with a prediction make a player eligible', () {
      expect(H2hLeaguePolicy.isEligible(4), isFalse);
      expect(H2hLeaguePolicy.isEligible(5), isTrue);
    });
  });

  group('H2hLeaguePolicy.opponentSlot', () {
    const capacity = H2hLeaguePolicy.groupCapacity;

    test('19 rounds meet every pair of 20 seats exactly once', () {
      final met = <String>{};
      for (var round = 1; round < capacity; round++) {
        final pairsThisRound = <String>{};
        for (var slot = 0; slot < capacity; slot++) {
          final other = H2hLeaguePolicy.opponentSlot(
            slot: slot,
            round: round,
            capacity: capacity,
          );
          expect(other, isNot(slot), reason: 'round $round slot $slot');
          expect(
            H2hLeaguePolicy.opponentSlot(
              slot: other,
              round: round,
              capacity: capacity,
            ),
            slot,
            reason: 'pairing is mutual in round $round',
          );
          final low = slot < other ? slot : other;
          final high = slot < other ? other : slot;
          pairsThisRound.add('$low-$high');
        }
        expect(pairsThisRound, hasLength(capacity ~/ 2));
        expect(met.intersection(pairsThisRound), isEmpty);
        met.addAll(pairsThisRound);
      }
      expect(met, hasLength(capacity * (capacity - 1) ~/ 2));
    });

    test('the first rounds pair the expected seats', () {
      expect(H2hLeaguePolicy.opponentSlot(slot: 0, round: 1, capacity: 20), 19);
      expect(H2hLeaguePolicy.opponentSlot(slot: 5, round: 1, capacity: 20), 14);
      expect(H2hLeaguePolicy.opponentSlot(slot: 0, round: 2, capacity: 20), 1);
    });
  });

  group('H2hLeaguePolicy.cut', () {
    test('twenty to a division, the rest to the open one', () {
      expect(H2hLeaguePolicy.seedDivision(0), H2hDivision.first);
      expect(H2hLeaguePolicy.seedDivision(19), H2hDivision.first);
      expect(H2hLeaguePolicy.seedDivision(20), H2hDivision.second);
      expect(H2hLeaguePolicy.seedDivision(59), H2hDivision.third);
      expect(H2hLeaguePolicy.seedDivision(60), H2hDivision.fourth);
      expect(H2hLeaguePolicy.seedDivision(200), H2hDivision.fourth);

      final entries = H2hLeaguePolicy.cut([
        for (var i = 0; i < 45; i++) UserId('p$i'),
      ]);
      expect(
        entries.where((e) => e.division == H2hDivision.first),
        hasLength(20),
      );
      expect(
        entries.where((e) => e.division == H2hDivision.second),
        hasLength(20),
      );
      expect(
        entries.where((e) => e.division == H2hDivision.third),
        hasLength(5),
      );
      expect(entries.first.userId, const UserId('p0'));
    });
  });

  group('H2hDivision and H2hLeagueOutcome', () {
    test('a stored level names its division, an unknown one none', () {
      expect(H2hDivision.ofLevel(1), H2hDivision.first);
      expect(H2hDivision.ofLevel(4), H2hDivision.fourth);
      expect(H2hDivision.ofLevel(5), isNull);
    });

    test('nothing leaves the top upwards or the open division downwards', () {
      expect(H2hDivision.first.canPromote, isFalse);
      expect(H2hDivision.fourth.canRelegate, isFalse);
      expect(H2hDivision.second.canPromote, isTrue);
      expect(H2hDivision.second.canRelegate, isTrue);
    });

    test('an outcome is read back from its wire name', () {
      expect(H2hLeagueOutcome.ofWire('promoted'), H2hLeagueOutcome.promoted);
      expect(H2hLeagueOutcome.ofWire('out'), H2hLeagueOutcome.out);
      expect(H2hLeagueOutcome.ofWire('x'), isNull);
    });
  });

  group('H2hLeaguePolicy.table', () {
    // Four seats, three rounds. Round 1: 0-3, 1-2. Round 2: 0-1, 2-3.
    // Round 3: 0-2, 1-3.
    final members = [
      _member('a', 0),
      _member('b', 1),
      _member('c', 2),
      _member('d', 3),
    ];
    final rounds = [_round(1, 3), _round(2, 5), _round(3, 7)];
    final scores = [
      _score('a', 1, points: 5, exact: 1, predicted: 2),
      _score('b', 1, points: 3, predicted: 2),
      _score('d', 1),
      _score('a', 2, points: 2),
      _score('b', 2, points: 2),
      _score('c', 2, points: 4, exact: 1),
    ];

    List<H2hPlacing> table() => H2hLeaguePolicy.order(
      H2hLeaguePolicy.table(
        capacity: 4,
        members: members,
        rounds: rounds,
        scores: scores,
      ),
    );

    test('more points win, equal points draw, both absent both lose', () {
      final a = table().first.standing;
      expect(a.userId, const UserId('a'));
      expect(a.matches.map((m) => m.result).toList(), [
        H2hMatchResult.win,
        H2hMatchResult.draw,
        H2hMatchResult.loss,
      ]);
      expect(a.matches.map((m) => m.opponentId).toList(), const [
        UserId('d'),
        UserId('b'),
        UserId('c'),
      ]);
      expect(a.matches.map((m) => m.day).toList(), [
        DateTime.utc(2026, 11, 3),
        DateTime.utc(2026, 11, 5),
        DateTime.utc(2026, 11, 7),
      ]);
      expect(a.won, 1);
      expect(a.drawn, 1);
      expect(a.lost, 1);
      expect(a.leaguePoints, 4);
      expect(a.pointsFor, 7);
      expect(a.exactCount, 1);
      expect(a.presentRounds, 2);
    });

    test('one who played beats one who did not, even with no points', () {
      final byUser = {
        for (final placing in table())
          placing.standing.userId.value: placing.standing,
      };
      // Round 1: c did not play, b did.
      expect(byUser['c']!.matches.first.result, H2hMatchResult.loss);
      expect(byUser['b']!.matches.first.result, H2hMatchResult.win);
      // Round 2: d did not play; c played and won.
      expect(byUser['c']!.matches[1].result, H2hMatchResult.win);
      // Round 1: d played, scored nothing, and lost to a's five.
      expect(byUser['d']!.matches.first.present, isTrue);
      expect(byUser['d']!.matches.first.result, H2hMatchResult.loss);
    });

    test('the table orders by league points, then prediction points', () {
      expect(
        table().map((p) => '${p.standing.userId.value}${p.rank}').toList(),
        ['a1', 'b2', 'c3', 'd4'],
      );
      final b = table()[1].standing;
      expect(b.leaguePoints, 4);
      expect(b.pointsFor, 5);
    });

    test('an empty seat plays the group average of the round', () {
      final standings = H2hLeaguePolicy.table(
        capacity: 4,
        members: [_member('a', 0), _member('b', 1)],
        rounds: [_round(1, 3)],
        scores: [_score('a', 1, points: 4), _score('b', 1, points: 2)],
      );
      // Round 1: 0-3 and 1-2; seats 2 and 3 are empty, the average is 3.
      final a = standings.firstWhere((s) => s.userId == const UserId('a'));
      final b = standings.firstWhere((s) => s.userId == const UserId('b'));
      expect(a.matches.single.opponentId, isNull);
      expect(a.matches.single.opponentPoints, 3);
      expect(a.matches.single.result, H2hMatchResult.win);
      expect(b.matches.single.result, H2hMatchResult.loss);
    });

    test('a member who did not play loses to the average', () {
      final standings = H2hLeaguePolicy.table(
        capacity: 4,
        members: [_member('a', 0)],
        rounds: [_round(1, 3)],
        scores: const <H2hRoundScore>[],
      );
      expect(standings.single.matches.single.result, H2hMatchResult.loss);
      expect(standings.single.presentRounds, 0);
    });
  });

  group('H2hLeaguePolicy.order', () {
    test('ties fall to points, exact calls, the earlier seat, the id', () {
      final placings = H2hLeaguePolicy.order([
        _standing('e', won: 1, pointsFor: 5, exact: 1, seatMinute: 1),
        _standing('d', won: 1, pointsFor: 5, exact: 1, seatMinute: 1),
        _standing('c', won: 1, pointsFor: 5, exact: 1),
        _standing('b', won: 1, pointsFor: 5, exact: 2),
        _standing('a', won: 1, pointsFor: 6),
        _standing('z', won: 2),
      ]);
      expect(placings.map((p) => p.standing.userId.value).toList(), [
        'z',
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
      expect(placings.map((p) => p.rank).toList(), [1, 2, 3, 4, 5, 6]);
    });

    test('the head-to-head between tied members comes before exact calls', () {
      final placings = H2hLeaguePolicy.order([
        _standing(
          'y',
          won: 1,
          lost: 1,
          pointsFor: 5,
          exact: 2,
          matches: [
            _match('x', H2hMatchResult.loss),
            _match('w', H2hMatchResult.win),
          ],
        ),
        _standing(
          'x',
          won: 1,
          lost: 1,
          pointsFor: 5,
          seatMinute: 9,
          matches: [
            _match('y', H2hMatchResult.win),
            _match('w', H2hMatchResult.loss),
          ],
        ),
      ]);
      expect(placings.map((p) => p.standing.userId.value).toList(), ['x', 'y']);
    });
  });

  group('H2hLeaguePolicy movement counts', () {
    test('three at most, never more than half', () {
      expect(H2hLeaguePolicy.promotionCount(H2hDivision.second, 20), 3);
      expect(H2hLeaguePolicy.promotionCount(H2hDivision.second, 5), 2);
      expect(H2hLeaguePolicy.promotionCount(H2hDivision.second, 1), 0);
      expect(H2hLeaguePolicy.promotionCount(H2hDivision.first, 20), 0);
      expect(H2hLeaguePolicy.relegationCount(H2hDivision.fourth, 20), 0);
      expect(H2hLeaguePolicy.relegationCount(H2hDivision.third, 20), 3);
    });
  });

  group('H2hLeaguePolicy.monthEnd', () {
    test('three cross each boundary and every division keeps its size', () {
      final groups = _standardMonth();
      final finishes = H2hLeaguePolicy.monthEnd(
        groups: groups,
        eligible: _everyone(groups),
      );
      final byUser = _byUser(finishes);

      expect(finishes, hasLength(70));
      expect(_countIn(finishes, H2hDivision.first), 20);
      expect(_countIn(finishes, H2hDivision.second), 20);
      expect(_countIn(finishes, H2hDivision.third), 20);
      expect(_countIn(finishes, H2hDivision.fourth), 10);

      for (final id in ['b01', 'b02', 'b03']) {
        expect(byUser[id]!.nextDivision, H2hDivision.first, reason: id);
        expect(byUser[id]!.outcome, H2hLeagueOutcome.promoted, reason: id);
      }
      for (final id in ['a18', 'a19', 'a20']) {
        expect(byUser[id]!.nextDivision, H2hDivision.second, reason: id);
        expect(byUser[id]!.outcome, H2hLeagueOutcome.relegated, reason: id);
      }
      for (final id in ['d01', 'd02', 'd03']) {
        expect(byUser[id]!.nextDivision, H2hDivision.third, reason: id);
      }
      for (final id in ['c18', 'c19', 'c20']) {
        expect(byUser[id]!.nextDivision, H2hDivision.fourth, reason: id);
      }
      expect(byUser['a17']!.outcome, H2hLeagueOutcome.held);
      expect(byUser['b04']!.outcome, H2hLeagueOutcome.held);
      expect(byUser['d04']!.outcome, H2hLeagueOutcome.held);
    });

    test('a member who was not active enough is not drawn, and the gap is '
        'filled from below', () {
      final groups = _standardMonth();
      final finishes = H2hLeaguePolicy.monthEnd(
        groups: groups,
        eligible: _everyone(groups, except: {'a19', 'a20'}),
      );
      final byUser = _byUser(finishes);

      expect(_countIn(finishes, null), 2);
      expect(_countIn(finishes, H2hDivision.first), 20);
      expect(_countIn(finishes, H2hDivision.second), 20);
      expect(_countIn(finishes, H2hDivision.third), 20);
      expect(_countIn(finishes, H2hDivision.fourth), 8);

      for (final id in ['a19', 'a20']) {
        expect(byUser[id]!.nextDivision, isNull, reason: id);
        expect(byUser[id]!.outcome, H2hLeagueOutcome.out, reason: id);
      }
      expect(byUser['a18']!.nextDivision, H2hDivision.second);
      for (final id in ['c01', 'c02', 'c03', 'c04', 'c05']) {
        expect(byUser[id]!.nextDivision, H2hDivision.second, reason: id);
      }
      expect(byUser['c06']!.nextDivision, H2hDivision.third);
      for (final id in ['d01', 'd02', 'd03', 'd04', 'd05']) {
        expect(byUser[id]!.nextDivision, H2hDivision.third, reason: id);
      }
      expect(byUser['d06']!.nextDivision, H2hDivision.fourth);
    });

    test('a seat freed in the top division goes to the best stayer below', () {
      final groups = _standardMonth();
      final finishes = H2hLeaguePolicy.monthEnd(
        groups: groups,
        eligible: _everyone(groups, except: {'a05'}),
      );
      final byUser = _byUser(finishes);

      expect(byUser['a05']!.outcome, H2hLeagueOutcome.out);
      for (final id in ['b01', 'b02', 'b03', 'b04']) {
        expect(byUser[id]!.nextDivision, H2hDivision.first, reason: id);
      }
      expect(byUser['b05']!.nextDivision, H2hDivision.second);
      expect(_countIn(finishes, H2hDivision.first), 20);
    });

    test('the open division promotes its group winners first', () {
      final groups = [
        _group(H2hDivision.first, 'a', 20),
        _group(H2hDivision.second, 'b', 20),
        _group(H2hDivision.third, 'c', 20),
        _group(H2hDivision.fourth, 'x', 17),
        _group(H2hDivision.fourth, 'y', 17),
        _group(H2hDivision.fourth, 'z', 17),
      ];
      final finishes = H2hLeaguePolicy.monthEnd(
        groups: groups,
        eligible: _everyone(groups),
      );
      final byUser = _byUser(finishes);

      for (final id in ['x01', 'y01', 'z01']) {
        expect(byUser[id]!.nextDivision, H2hDivision.third, reason: id);
        expect(byUser[id]!.outcome, H2hLeagueOutcome.promoted, reason: id);
      }
      for (final id in ['x02', 'y02', 'z02']) {
        expect(byUser[id]!.outcome, H2hLeagueOutcome.held, reason: id);
      }
      expect(_countIn(finishes, H2hDivision.fourth), 51);
    });
  });

  group('H2hLeaguePolicy.draw', () {
    test('even groups, the top of the order spread across them', () {
      final entries = H2hLeaguePolicy.cut([
        for (var i = 0; i < 111; i++)
          UserId('p${i.toString().padLeft(3, '0')}'),
      ]);
      final groups = H2hLeaguePolicy.draw(entries);

      expect(
        groups.map((g) => '${g.division.level}/${g.groupIndex}').toList(),
        ['1/0', '2/0', '3/0', '4/0', '4/1', '4/2'],
      );
      expect(groups.map((g) => g.seats.length).toList(), [
        20,
        20,
        20,
        17,
        17,
        17,
      ]);
      expect(groups.first.seats.first.userId, const UserId('p000'));
      expect(
        groups.first.seats.map((s) => s.slot).toList(),
        List<int>.generate(20, (i) => i),
      );

      final open = groups.sublist(3);
      expect(open[0].seats[0].userId, const UserId('p060'));
      expect(open[1].seats[0].userId, const UserId('p061'));
      expect(open[2].seats[0].userId, const UserId('p062'));
      expect(open[0].seats[1].userId, const UserId('p063'));
      expect(open[0].seats[1].slot, 1);
    });

    test('a division nobody was drawn into opens no group', () {
      final groups = H2hLeaguePolicy.draw([
        const H2hDrawEntry(userId: UserId('a'), division: H2hDivision.fourth),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.division, H2hDivision.fourth);
      expect(groups.single.seats.single.slot, 0);
    });
  });
}
