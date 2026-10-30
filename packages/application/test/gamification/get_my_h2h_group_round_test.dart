import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
const _league = H2hLeagueId('33333333-3333-4333-8333-333333333333');
final _me = player.userId;
final _u2 = userNo(2);
final _u3 = userNo(3);
final _u4 = userNo(4);

H2hRound _round(
  int number,
  int day, {
  required bool locked,
  DateTime? monthStart,
}) {
  final month = monthStart ?? _november;
  return H2hRound(
    id: H2hRoundId('44444444-4444-4444-8444-00000000000$number'),
    monthStart: month,
    number: number,
    day: DateTime.utc(month.year, month.month, day),
    fixtureCount: 6,
    approvedBy: null,
    lockedAt: locked ? DateTime.utc(month.year, month.month, day, 12) : null,
  );
}
// NK172_077

H2hRoundScore _score(UserId user, int round, int points) => H2hRoundScore(
  userId: user,
  round: round,
  points: points,
  exactCount: 0,
  predictedCount: 2,
);

/// Round 2's last fixture that counts kicks off at 14:00 on the 5th.
final _lastOfRound2 = DateTime.utc(2026, 11, 5, 14);

/// Four seats. Round 1: 0-3, 1-2. Round 2: 0-1, 2-3. Round 3: 0-2, 1-3.
/// Round 4 pairs as round 1. Round 1 settled, 2 live, 3 void, 4 ahead.
/// Read at 15:00 on the 5th unless [now] says otherwise.
Future<Result<MyH2hGroupRound>> _read({
  required int round,
  int mySlot = 0,
  bool withU4 = true,
  AuthenticatedUser principal = player,
  bool seated = true,
  DateTime? now,
  List<int> turns = const <int>[],
  DateTime? monthStart,
  bool absentU4 = false,
  bool presentU3 = false,
}) {
  final month = monthStart ?? _november;
  final leagues = FakeH2hLeagueStore();
  // NK172_078
  if (seated) {
    leagues.seat(
      _me,
      H2hSeat(
        leagueId: _league,
        monthStart: month,
        // NK172_079
        division: H2hDivision.second,
        groupIndex: 0,
        slot: mySlot,
        capacity: 4,
        divisionGroups: 1,
        isPilot: false,
        joinedAt: month,
        // NK172_080
      ),
    );
  }
  final rounds = FakeH2hRoundStore()
    ..addRound(_round(1, 3, locked: true, monthStart: month))
    ..addRound(_round(2, 5, locked: true, monthStart: month))
    ..addRound(_round(3, 7, locked: true, monthStart: month))
    ..addRound(_round(4, 9, locked: false, monthStart: month));
  // NK172_081
  // The caller takes [mySlot]; the others fill the remaining seats in order.
  final others = <UserId>[_u2, _u3, if (withU4) _u4];
  final seats = <int, UserId>{mySlot: _me};
  var next = 0;
  for (final user in others) {
    while (seats.containsKey(next)) {
      next++;
    }
    seats[next] = user;
  }
  final sheets = FakeH2hSheetReader()
    ..sheets[_league] = H2hGroupSheet(
      members: [
        for (final entry in seats.entries)
          H2hMember(
            userId: entry.value,
            slot: entry.key,
            joinedAt: DateTime.utc(month.year, month.month, 1, 0, entry.key),
            // NK172_082
          ),
      ],
      scores: [
        // Round 1, settled: the caller 5, u4 2, u2 and u3 played nothing.
        _score(_me, 1, 5),
        if (presentU3) _score(_u3, 1, 4),
        if (withU4 && !absentU4) _score(_u4, 1, 2),
        // Round 2, live: the caller 1, u2 4; u3 nothing yet, u4 0.
        // NK172_083
        _score(_me, 2, 1),
        _score(_u2, 2, 4),
        if (withU4) _score(_u4, 2, 0),
      ],
      settledRounds: const <int>{1},
      voidRounds: const <int>{3},
      turns: turns,
      lastKickoffs: {
        1: DateTime.utc(month.year, month.month, 3, 20),
        2: DateTime.utc(month.year, month.month, 5, 14),
      },
      // NK172_084
    );
  return GetMyH2hGroupRound(
    league: GetMyH2hLeague(
      leagues: leagues,
      rounds: rounds,
      sheets: sheets,
      profiles: NamingProfiles(),
      clock: AtClock(now ?? DateTime.utc(month.year, month.month, 5, 15)),
      // NK172_085
    ),
    sheets: sheets,
  ).call(principal: principal, round: round);
}

MyH2hGroupRound _ok(Result<MyH2hGroupRound> result) =>
    (result as Ok<MyH2hGroupRound>).value;

void main() {
  test('a settled round: every pair with the policy result', () async {
    final group = _ok(await _read(round: 1));

    expect(group.phase, H2hRoundPhase.settled);
    expect(group.pairs, hasLength(2));
    final mine = group.pairs.first;
    expect((mine.home, mine.away), (_me, _u4));
    expect((mine.homePoints, mine.awayPoints), (5, 2.0));
    expect(mine.winner, H2hPairWinner.home);
    // Neither u2 nor u3 predicted: the policy gives both a loss.
    final theirs = group.pairs.last;
    expect((theirs.home, theirs.away), (_u2, _u3));
    expect(theirs.winner, H2hPairWinner.none);
    expect(group.profiles[_u3]!.displayName, 'name ${_u3.value}');
  });

  // NK172 group round December absence test
  test(
    'December absent opponents use the average in every visible pair',
    () async {
      final group = _ok(
        await _read(
          round: 1,
          monthStart: DateTime.utc(2026, 12),
          absentU4: true,
          presentU3: true,
          now: DateTime.utc(2026, 12, 3, 21),
        ),
      );

      expect(group.phase, H2hRoundPhase.settled);
      final mine = group.pairs.first;
      expect((mine.home, mine.away), (_me, _u4));
      expect(mine.awayAbsent, isTrue);
      expect(mine.awayPoints, 2.25);
      expect(mine.winner, H2hPairWinner.home);

      final others = group.pairs.last;
      expect((others.home, others.away), (_u3, _u2));
      expect(others.awayAbsent, isTrue);
      expect(others.awayPoints, 2.25);
      expect(others.winner, H2hPairWinner.home);
    },
  );

  test('a live round before its last kickoff: no pairs at all', () async {
    // NK172_086
    final group = _ok(
      await _read(round: 2, now: DateTime.utc(2026, 11, 5, 13, 59)),
    );

    expect(group.phase, H2hRoundPhase.live);
    expect(group.pairsHidden, isTrue);
    expect(group.pairs, isEmpty);
    expect(group.revealsAt, _lastOfRound2);
  });

  test('a live round after its last kickoff: points only, never who has '
      'not predicted', () async {
    final group = _ok(await _read(round: 2));

    expect(group.phase, H2hRoundPhase.live);
    expect(group.pairsHidden, isFalse);
    expect(group.revealsAt, isNull);
    final mine = group.pairs.first;
    expect((mine.home, mine.away), (_me, _u2));
    expect(mine.winner, H2hPairWinner.away);
    // u3 has no pick yet and u4 has 0: the policy would give u4 the win.
    final theirs = group.pairs.last;
    expect((theirs.home, theirs.away), (_u3, _u4));
    expect((theirs.homePoints, theirs.awayPoints), (0, 0.0));
    expect(theirs.winner, H2hPairWinner.draw);
  });

  test('a void round: the pairs, no points', () async {
    final group = _ok(await _read(round: 3));

    expect(group.phase, H2hRoundPhase.voided);
    expect(group.pairs.map((p) => (p.home, p.away)).toList(), [
      (_me, _u3),
      (_u2, _u4),
    ]);
    for (final pair in group.pairs) {
      expect(pair.homePoints, isNull);
      expect(pair.awayPoints, isNull);
      expect(pair.winner, isNull);
    }
  });

  test('a round ahead: nobody knows who meets whom', () async {
    final group = _ok(await _read(round: 4));

    expect(group.phase, H2hRoundPhase.open);
    expect(group.pairsHidden, isTrue);
    expect(group.pairs, isEmpty);
    expect(group.revealsAt, isNull);
  });

  test('the group secret order decides who meets whom', () async {
    // Round 1 plays turn 2: 0-1, 2-3.
    final group = _ok(await _read(round: 1, turns: const [2, 3, 1]));

    expect(group.pairs.map((p) => (p.home, p.away)).toList(), [
      (_me, _u2),
      (_u3, _u4),
    ]);
    // The caller's 5 against u2, who played nothing.
    expect(group.pairs.first.winner, H2hPairWinner.home);
  });

  test('the caller comes first and on the first side, whatever the seat', () {
    return _read(round: 1, mySlot: 2).then((result) {
      final group = _ok(result);
      // Round 1: slot 0 (u2) meets slot 3 (u4); the caller (2) meets u3 (1).
      expect((group.pairs.first.home, group.pairs.first.away), (_me, _u3));
      expect((group.pairs.last.home, group.pairs.last.away), (_u2, _u4));
    });
  });

  test('an empty seat plays the group average', () async {
    final group = _ok(await _read(round: 1, withU4: false));

    final mine = group.pairs.first;
    expect(mine.home, _me);
    expect(mine.away, isNull);
    // (5 + 0 + 0) / 3 members.
    expect(mine.awayPoints, closeTo(5 / 3, 1e-9));
    expect(mine.winner, H2hPairWinner.home);
  });

  test('a caller with no seat is refused', () async {
    final result = await _read(round: 1, seated: false);

    expect((result as Err<MyH2hGroupRound>).error.code, 'h2h.not_seated');
  });

  test('a round the month does not have is refused', () async {
    final result = await _read(round: 9);

    expect((result as Err<MyH2hGroupRound>).error.code, 'h2h.round_unknown');
  });
}
