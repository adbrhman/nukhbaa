import 'dart:math';

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

  group('H2hLeaguePolicy.turnOf', () {
    test('without an order, round n plays turn n', () {
      for (var round = 1; round <= 19; round++) {
        expect(
          H2hLeaguePolicy.turnOf(round: round, turns: const <int>[]),
          round,
        );
      }
    });

    test('with an order, round n plays its n-th turn, again past the end', () {
      const turns = [3, 1, 2];
      expect(
        [
          for (var round = 1; round <= 7; round++)
            H2hLeaguePolicy.turnOf(round: round, turns: turns),
        ],
        [3, 1, 2, 3, 1, 2, 3],
      );
    });

    test('any order of the 19 turns still meets every pair once', () {
      const capacity = H2hLeaguePolicy.groupCapacity;
      final turns = [for (var t = 19; t >= 1; t--) t]..shuffle(Random(7));
      final met = <String>{};
      for (var round = 1; round < capacity; round++) {
        for (var slot = 0; slot < capacity; slot++) {
          final other = H2hLeaguePolicy.opponentSlot(
            slot: slot,
            round: H2hLeaguePolicy.turnOf(round: round, turns: turns),
            capacity: capacity,
          );
          final low = slot < other ? slot : other;
          final high = slot < other ? other : slot;
          met.add('$low-$high');
        }
      }
      expect(met, hasLength(capacity * (capacity - 1) ~/ 2));
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

    test('the secret order decides who met whom', () {
      // Turns 3, 1, 2: round 1 is 0-2 / 1-3, round 2 is 0-3 / 1-2, round 3
      // is 0-1 / 2-3.
      final a = H2hLeaguePolicy.table(
        capacity: 4,
        members: members,
        rounds: rounds,
        scores: scores,
        turns: const [3, 1, 2],
      ).singleWhere((s) => s.userId == const UserId('a'));
      expect(a.matches.map((m) => m.opponentId).toList(), const [
        UserId('c'),
        UserId('d'),
        UserId('b'),
      ]);
      // Round 1: a's 5 against c, who did not play.
      expect(a.matches.first.result, H2hMatchResult.win);
      // Round 3: a and b both absent.
      expect(a.matches.last.result, H2hMatchResult.loss);
    });

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

    // NK172 December policy tests
    test('the month gate leaves November intact and begins in December', () {
      expect(
        H2hLeaguePolicy.usesDecemberRules(DateTime.utc(2026, 11, 30)),
        isFalse,
      );
      expect(
        H2hLeaguePolicy.usesDecemberRules(DateTime.utc(2026, 12, 1)),
        isTrue,
      );
      expect(
        H2hLeaguePolicy.usesDecemberRules(DateTime.utc(2027, 1, 1)),
        isTrue,
      );
    });

    // NK216: the walkover rule replaces the December average comparison.
    test('the walkover rule begins at round 7 of November 2026', () {
      bool uses(int month, int round, {int year = 2026}) =>
          H2hLeaguePolicy.usesWalkoverRule(
            day: DateTime.utc(year, month, 8),
            round: round,
          );
      expect(H2hLeaguePolicy.walkoverFirstRound, 7);
      expect(uses(11, 6), isFalse);
      expect(uses(11, 7), isTrue);
      expect(uses(11, 19), isTrue);
      expect(uses(12, 1), isTrue);
      expect(uses(1, 1, year: 2027), isTrue);
      expect(uses(10, 12), isFalse);
    });

    test(
      'a walkover is won only with a correct prediction, else one point',
      () {
        final members = [
          _member('a', 0),
          _member('b', 1),
          _member('c', 2),
          _member('d', 3),
        ];
        final decemberRound = [
          H2hRoundRef(number: 1, day: DateTime.utc(2026, 12, 3)),
        ];
        H2hMatch matchOf(String id, List<H2hRoundScore> roundScores) =>
            H2hLeaguePolicy.table(
              capacity: 4,
              members: members,
              rounds: decemberRound,
              scores: roundScores,
            ).singleWhere((s) => s.userId == UserId(id)).matches.single;

        // d is a's opponent in round 1 and did not play.
        final scored = [
          _score('a', 1, points: 6),
          _score('b', 1, points: 4),
          _score('c', 1, points: 5),
        ];
        expect(matchOf('a', scored).opponentId, const UserId('d'));
        expect(matchOf('a', scored).opponentPresent, isFalse);
        expect(matchOf('a', scored).opponentPoints, 0);
        expect(matchOf('a', scored).result, H2hMatchResult.win);
        expect(matchOf('d', scored).result, H2hMatchResult.loss);

        // a played but called nothing right: one point, a draw's worth.
        final nothing = [
          _score('a', 1),
          _score('b', 1, points: 4),
          _score('c', 1, points: 5),
        ];
        expect(matchOf('a', nothing).result, H2hMatchResult.draw);
        expect(matchOf('a', nothing).result.leaguePoints, 1);
        expect(matchOf('d', nothing).result, H2hMatchResult.loss);

        // Both absent: both lose.
        final neither = [_score('b', 1, points: 4), _score('c', 1, points: 5)];
        expect(matchOf('a', neither).result, H2hMatchResult.loss);
        expect(matchOf('d', neither).result, H2hMatchResult.loss);
      },
    );

    test('before round 7 of November an absent opponent still loses', () {
      final members = [_member('a', 0), _member('b', 1)];
      H2hMatch aIn(int number) => H2hLeaguePolicy.table(
        capacity: 2,
        members: members,
        rounds: [_round(number, 10)],
        scores: [_score('a', number)],
        turns: const [1],
      ).singleWhere((s) => s.userId == const UserId('a')).matches.single;

      // a played with no points, b did not play.
      expect(aIn(6).result, H2hMatchResult.win);
      expect(aIn(7).result, H2hMatchResult.draw);
    });
    // NK172_059
  });

  // NK216: a seat's record stays with the seat, from a swap at round 7.
  group('H2hLeaguePolicy.seatRecords', () {
    H2hMember holder(String id, int slot, {int from = 1, int? until}) =>
        H2hMember(
          userId: UserId(id),
          slot: slot,
          joinedAt: DateTime.utc(2026, 11, 1, 3, slot),
          fromRound: from,
          untilRound: until,
        );
    final november = DateTime.utc(2026, 11, 8);

    test('a swap from round 7 passes the seat record to the new holder', () {
      final records = H2hLeaguePolicy.seatRecords(
        members: [holder('a', 0, until: 6), holder('b', 0, from: 7)],
        table: [_standing('a', won: 2), _standing('b', won: 1)],
        day: november,
      );
      expect(records.kept.containsKey(const UserId('a')), isFalse);
      expect(records.given[const UserId('a')]!.single.won, 2);
      expect(records.kept[const UserId('b')]!.single.won, 1);
      expect(records.taken[const UserId('b')]!.single.won, 2);
      expect(records.taken.containsKey(const UserId('a')), isFalse);
    });

    test('a swap before round 7 of November keeps each his own part', () {
      final records = H2hLeaguePolicy.seatRecords(
        members: [holder('a', 0, until: 4), holder('b', 0, from: 5)],
        table: [_standing('a', won: 2), _standing('b', won: 1)],
        day: november,
      );
      expect(records.kept[const UserId('a')]!.single.won, 2);
      expect(records.kept[const UserId('b')]!.single.won, 1);
      expect(records.given, isEmpty);
      expect(records.taken, isEmpty);
    });

    test('from December every swap passes the seat record on', () {
      final records = H2hLeaguePolicy.seatRecords(
        members: [holder('a', 0, until: 1), holder('b', 0, from: 2)],
        table: [_standing('a', won: 1), _standing('b', won: 1)],
        day: DateTime.utc(2026, 12, 9),
      );
      expect(records.given.containsKey(const UserId('a')), isTrue);
      expect(records.taken.containsKey(const UserId('b')), isTrue);
    });

    test('a seat swapped twice hands the whole chain to the last holder', () {
      final records = H2hLeaguePolicy.seatRecords(
        members: [
          holder('a', 0, until: 6),
          holder('b', 0, from: 7, until: 11),
          holder('c', 0, from: 12),
        ],
        table: [
          _standing('a', won: 2),
          _standing('b', won: 3),
          _standing('c', won: 1),
        ],
        day: november,
      );
      expect(records.kept.keys, [const UserId('c')]);
      expect(records.given.keys, [const UserId('a'), const UserId('b')]);
      expect(records.taken[const UserId('b')], isNull);
      expect(records.taken[const UserId('c')]!.map((s) => s.won), [2, 3]);
    });

    test('a swap before round 7 followed by one after it', () {
      final records = H2hLeaguePolicy.seatRecords(
        members: [
          holder('a', 0, until: 4),
          holder('b', 0, from: 5, until: 8),
          holder('c', 0, from: 9),
        ],
        table: [
          _standing('a', won: 2),
          _standing('b', won: 3),
          _standing('c', won: 1),
        ],
        day: november,
      );
      // a keeps his own part; only b's rounds pass to c.
      expect(records.kept[const UserId('a')]!.single.won, 2);
      expect(records.given.keys, [const UserId('b')]);
      expect(records.taken[const UserId('c')]!.single.won, 3);
    });

    test('a member with no standing breaks the chain', () {
      final records = H2hLeaguePolicy.seatRecords(
        members: [holder('a', 0, until: 6), holder('b', 0, from: 7)],
        table: [_standing('b', won: 1)],
        day: november,
      );
      expect(records.given, isEmpty);
      expect(records.taken, isEmpty);
      expect(records.kept[const UserId('b')]!.single.won, 1);
    });

    test('two seats swapped from round 7 trade their records', () {
      // a leaves seat 0 of the elite group for seat 5 of the extra group,
      // and b takes the opposite way.
      final elite = H2hLeaguePolicy.seatRecords(
        members: [holder('a', 0, until: 6), holder('b', 0, from: 7)],
        table: [_standing('a', won: 4), _standing('b', won: 0)],
        day: november,
      );
      final extra = H2hLeaguePolicy.seatRecords(
        members: [holder('b', 5, until: 6), holder('a', 5, from: 7)],
        table: [_standing('b', won: 1), _standing('a', won: 0)],
        day: november,
      );
      final a = H2hLeaguePolicy.mergeStandings(
        parts: [
          ...?extra.kept[const UserId('a')],
          ...?elite.kept[const UserId('a')],
        ],
        seat: holder('a', 5, from: 7),
        given: [...?elite.given[const UserId('a')]],
        taken: [...?extra.taken[const UserId('a')]],
      );
      final b = H2hLeaguePolicy.mergeStandings(
        parts: [
          ...?elite.kept[const UserId('b')],
          ...?extra.kept[const UserId('b')],
        ],
        seat: holder('b', 0, from: 7),
        given: [...?extra.given[const UserId('b')]],
        taken: [...?elite.taken[const UserId('b')]],
      );
      // The relegated a takes the extra seat's record (1 win), the promoted
      // b takes the elite seat's record (4 wins).
      expect(a.won, 1);
      expect(b.won, 4);
    });
  });

  group('H2hLeaguePolicy.mergeStandings', () {
    final seat = H2hMember(
      userId: const UserId('b'),
      slot: 0,
      joinedAt: DateTime.utc(2026, 11, 1),
      fromRound: 7,
    );

    test('without a swap the parts add up as before', () {
      final merged = H2hLeaguePolicy.mergeStandings(
        parts: [
          _standing(
            'b',
            won: 1,
            pointsFor: 5,
            matches: [_match('x', H2hMatchResult.win)],
          ),
          _standing(
            'b',
            drawn: 1,
            pointsFor: 2,
            matches: [_match('y', H2hMatchResult.draw)],
          ),
        ],
        seat: seat,
      );
      expect(merged.won, 1);
      expect(merged.drawn, 1);
      expect(merged.pointsFor, 7);
      expect(merged.matches, hasLength(2));
      expect(merged.counted, isNull);
      expect(merged.countedMatches, same(merged.matches));
    });

    test('a taken part counts in the totals, a given one only as matches', () {
      final merged = H2hLeaguePolicy.mergeStandings(
        parts: [
          _standing(
            'b',
            won: 1,
            pointsFor: 4,
            exact: 1,
            matches: [_match('x', H2hMatchResult.win)],
          ),
        ],
        seat: seat,
        given: [
          _standing(
            'b',
            won: 5,
            pointsFor: 50,
            matches: [_match('g', H2hMatchResult.win)],
          ),
        ],
        taken: [
          _standing(
            'a',
            won: 2,
            drawn: 1,
            lost: 1,
            pointsFor: 30,
            exact: 3,
            matches: [_match('t', H2hMatchResult.loss)],
          ),
        ],
      );
      expect(merged.won, 3);
      expect(merged.drawn, 1);
      expect(merged.lost, 1);
      expect(merged.pointsFor, 34);
      expect(merged.exactCount, 4);
      expect(merged.leaguePoints, 10);
      // His own matches: the kept and the given ones, not the taken.
      expect(merged.matches.map((m) => m.opponentId?.value).toSet(), {
        'x',
        'g',
      });
      // The matches behind the totals: the kept and the taken ones.
      expect(merged.countedMatches.map((m) => m.opponentId?.value).toSet(), {
        'x',
        't',
      });
    });

    test('the head-to-head reads the matches behind the totals', () {
      // b took p's record, and p drew with a: that draw counts for b against
      // a, who lost to b in a match of his own. Level on 4 league points and
      // 0 prediction points, b is ahead of a although a's id comes first.
      final b = H2hLeaguePolicy.mergeStandings(
        parts: [
          _standing('b', won: 1, matches: [_match('z', H2hMatchResult.win)]),
        ],
        seat: seat,
        taken: [
          _standing('p', drawn: 1, matches: [_match('a', H2hMatchResult.draw)]),
        ],
      );
      final a = _standing(
        'a',
        won: 1,
        drawn: 1,
        matches: [_match('b', H2hMatchResult.loss)],
      );
      expect(b.leaguePoints, a.leaguePoints);
      final placings = H2hLeaguePolicy.order([a, b]);
      expect(placings.first.standing.userId, const UserId('b'));
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
        monthStart: DateTime.utc(2026, 11),
      );
      // NK172_060

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
        monthStart: DateTime.utc(2026, 11),
      )
      // NK172_061
      ;
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
        monthStart: DateTime.utc(2026, 11),
      )
      // NK172_062
      ;
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
        monthStart: DateTime.utc(2026, 11),
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

    test(
      'December compares group rank, prediction points, exacts, then league points',
      () {
        H2hGroupResult fourthGroup(
          String prefix,
          String leader, {
          required int wins,
          required int points,
          required int exact,
        }) => H2hGroupResult(
          division: H2hDivision.fourth,
          placings: [
            H2hPlacing(
              rank: 1,
              standing: _standing(
                leader,
                won: wins,
                pointsFor: points,
                exact: exact,
              ),
            ),
            for (var rank = 2; rank <= 16; rank++)
              H2hPlacing(
                rank: rank,
                standing: _standing(
                  '$prefix${rank.toString().padLeft(2, '0')}',
                  won: 100 - rank,
                ),
              ),
          ],
        );

        final groups = [
          _group(H2hDivision.first, 'first', 20),
          _group(H2hDivision.second, 'second', 20),
          _group(H2hDivision.third, 'third', 20),
          fourthGroup('a', 'a-leader', wins: 1, points: 100, exact: 1),
          fourthGroup('b', 'b-leader', wins: 0, points: 100, exact: 3),
          fourthGroup('c', 'c-leader', wins: 33, points: 90, exact: 9),
          fourthGroup('d', 'd-leader', wins: 34, points: 90, exact: 4),
          fourthGroup('e', 'e-leader', wins: 35, points: 80, exact: 99),
        ];
        final eligible = _everyone(groups);

        List<String> promoted(DateTime monthStart) {
          final finishes = H2hLeaguePolicy.monthEnd(
            groups: groups,
            eligible: eligible,
            monthStart: monthStart,
          );
          return [
            for (final finish in finishes)
              if (finish.division == H2hDivision.fourth &&
                  finish.nextDivision == H2hDivision.third)
                finish.placing.standing.userId.value,
          ];
        }

        expect(promoted(DateTime.utc(2026, 11)), [
          'e-leader',
          'd-leader',
          'c-leader',
        ]);
        expect(promoted(DateTime.utc(2026, 12)), [
          'b-leader',
          'a-leader',
          'c-leader',
        ]);
      },
    );
    // NK172_063
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
