/// The carry of an elite month (NK275, decided by the owner on 2026-11-14):
/// the last three of each elite group go down, the elite's free seats go to
/// the most committed of groups 5 and 6, the last five of an extra group go
/// down and the five most committed of the group below come up, and the
/// eighty are dealt again by the month.
library;

import 'package:domain/domain.dart';
import 'package:test/test.dart';

UserId _u(int i) =>
    UserId('00000000-0000-4000-8275-${i.toString().padLeft(12, '0')}');

H2hPlacing _placing(int user, int rank, {int points = 0}) => H2hPlacing(
  rank: rank,
  standing: H2hStanding(
    userId: _u(user),
    slot: rank - 1,
    joinedAt: DateTime.utc(2026, 11),
    won: 0,
    drawn: 0,
    lost: 0,
    pointsFor: points,
    exactCount: 0,
    presentRounds: 0,
    matches: const <H2hMatch>[],
  ),
);

/// A group of [size] whose users are [first], [first] + 1, ... in the order
/// of its table (the first is ranked 1).
H2hEliteGroup _group(H2hDivision division, int index, int first, int size) =>
    H2hEliteGroup(
      division: division,
      groupIndex: index,
      placings: [
        for (var k = 0; k < size; k++)
          _placing(first + k, k + 1, points: 99 - k),
      ],
    );

H2hCommitment _c({int absent = 0, int predicted = 50, int exact = 0}) =>
    H2hCommitment(
      absentRounds: absent,
      predicted: predicted,
      exact: exact,
      outcomes: 0,
      points: 0,
    );

void main() {
  // Four elite groups of 20 (users 0..79), group 5 (100..119), group 6
  // (200..219) and group 7 (300..309).
  final groups = <H2hEliteGroup>[
    for (var g = 0; g < 4; g++)
      _group(H2hLeaguePolicy.eliteDivision, g, g * 20, 20),
    _group(H2hLeaguePolicy.extraDivision, 0, 100, 20),
    _group(H2hLeaguePolicy.extraDivision, 1, 200, 20),
    _group(H2hLeaguePolicy.extraDivision, 2, 300, 10),
  ];
  final everyone = <int>[
    for (var i = 0; i < 80; i++) i,
    for (var i = 100; i < 120; i++) i,
    for (var i = 200; i < 220; i++) i,
    for (var i = 300; i < 310; i++) i,
  ];
  // Everyone missed four rounds, except: in group 5 users 110..117 missed
  // none, in group 6 users 200..203 missed none, and in group 7 users
  // 300..304 missed one.
  final commitment = <UserId, H2hCommitment>{
    for (final i in everyone) _u(i): _c(absent: 4),
    for (var i = 110; i < 118; i++) _u(i): _c(predicted: 60 + i - 110),
    for (var i = 200; i < 204; i++) _u(i): _c(),
    for (var i = 300; i < 305; i++) _u(i): _c(absent: 1),
  };

  List<H2hEliteFinish> carry({Set<int> out = const <int>{}}) =>
      H2hEliteCarry.next(
        groups: groups,
        eligible: {
          for (final i in everyone)
            if (!out.contains(i)) _u(i),
        },
        commitment: commitment,
      );

  Map<int, H2hEliteFinish> byUser(List<H2hEliteFinish> finishes) => {
    for (final f in finishes)
      everyone.firstWhere((i) => _u(i) == f.placing.standing.userId): f,
  };

  test('every member once; the order is 0..n-1 with no gap', () {
    final finishes = carry();
    expect(finishes, hasLength(everyone.length));
    final orders = [for (final f in finishes) f.nextOrder!]..sort();
    expect(orders, [for (var i = 0; i < everyone.length; i++) i]);
  });

  test('the last three of each elite group go down to group 5', () {
    final f = byUser(carry());
    for (var g = 0; g < 4; g++) {
      for (var k = 0; k < 20; k++) {
        final user = f[g * 20 + k]!;
        if (k < 17) {
          expect(user.outcome, H2hLeagueOutcome.held, reason: '${g * 20 + k}');
          expect(user.nextOrder, lessThan(80));
        } else {
          expect(user.outcome, H2hLeagueOutcome.relegated);
          expect(user.nextDivision, H2hLeaguePolicy.extraDivision);
          expect(user.nextOrder, greaterThanOrEqualTo(80));
        }
      }
    }
  });

  test('the twelve seats go to the most committed of groups 5 and 6', () {
    final f = byUser(carry());
    final up = [
      for (final e in f.entries)
        if (e.value.outcome == H2hLeagueOutcome.promoted &&
            e.value.nextDivision == H2hLeaguePolicy.eliteDivision)
          e.key,
    ]..sort();
    // 110..117 and 200..203 missed nothing; group 7's 300..304 missed one
    // and are not looked at while groups 5 and 6 have enough.
    expect(up, [for (var i = 110; i < 118; i++) i, 200, 201, 202, 203]);
    // The eighty are the 68 who stayed, ranked by the month, then the
    // twelve, the most committed first.
    expect(f[117]!.nextOrder, 68); // predicted 67, the most
    // The month's ranking: the place in the group first, so the four
    // leaders (0, 20, 40, 60) open the list, then the four seconds.
    expect(f[0]!.nextOrder, 0);
    expect(f[20]!.nextOrder, 1);
    expect(f[60]!.nextOrder, 3);
    expect(f[1]!.nextOrder, 4);
  });

  test(
    'between extra groups: five down by the table, five up by commitment',
    () {
      final f = byUser(carry());
      // Group 6 -> 7: its last five by the table (215..219) go down.
      for (var i = 215; i < 220; i++) {
        expect(f[i]!.outcome, H2hLeagueOutcome.relegated, reason: '$i');
      }
      // Group 7 -> 6: the five most committed (300..304) come up.
      for (var i = 300; i < 305; i++) {
        expect(f[i]!.outcome, H2hLeagueOutcome.promoted, reason: '$i');
        expect(f[i]!.nextDivision, H2hLeaguePolicy.extraDivision);
      }
      // The last group sends nobody down.
      for (var i = 305; i < 310; i++) {
        expect(f[i]!.outcome, H2hLeagueOutcome.held, reason: '$i');
      }
    },
  );

  test('a member who predicted on too few days is not carried', () {
    final f = byUser(carry(out: {5, 105}));
    expect(f[5]!.outcome, H2hLeagueOutcome.out);
    expect(f[5]!.nextDivision, isNull);
    expect(f[5]!.nextOrder, isNull);
    expect(f[105]!.outcome, H2hLeagueOutcome.out);
    // The elite still opens with eighty: one more comes up.
    final elite = [
      for (final e in f.values)
        if (e.nextDivision == H2hLeaguePolicy.eliteDivision) e,
    ];
    expect(elite, hasLength(80));
  });

  test('the more committed first: absences, then predictions, then exact', () {
    final m = <UserId, H2hCommitment>{
      _u(1): _c(absent: 1, predicted: 90),
      _u(2): _c(predicted: 10),
      _u(3): _c(predicted: 10, exact: 3),
    };
    final order = [_u(1), _u(2), _u(3)]
      ..sort((a, b) => H2hEliteCarry.compareCommitment(a, b, m));
    expect(order, [_u(3), _u(2), _u(1)]);
  });
}
