/// A seat's record stays with the seat (NK216, owner's decision of
/// 2026-11-07): from a swap at round 7 of November 2026 whoever takes a seat
/// takes the league points, prediction points and exact scorelines it had,
/// and whoever leaves it takes those of the seat he moves to. A swap before
/// round 7 keeps the earlier rule: each player keeps his own month.
///
/// Through [H2hMonthBook], the one place that puts a player's month together
/// from the groups he held a seat in.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

const _elite = H2hLeagueId('33333333-3333-4333-8333-333333333333');
const _extra = H2hLeagueId('44444444-4444-4444-8444-444444444444');

H2hRoundScore _score(int user, int round, int points) => H2hRoundScore(
  userId: userNo(user),
  round: round,
  points: points,
  exactCount: 1,
  predictedCount: 1,
);

List<H2hRoundRef> _rounds(int count) => [
  for (var number = 1; number <= count; number++)
    H2hRoundRef(number: number, day: DateTime.utc(2026, 11, number)),
];

/// Two groups of four seats: the elite group (players 1 to 4) and the extra
/// one (players 5 to 8). At round [swapRound] player 1 leaves seat 0 of the
/// elite group for seat 0 of the extra group, and player 5 comes the other
/// way. Player 1 predicts rounds 1 to 6 with 3 points each, player 5 rounds
/// 1, 2, 7 and 8; everybody else never predicts.
H2hMonthBook _book({required int swapRound}) {
  final scores = [
    for (var round = 1; round <= 6; round++) _score(1, round, 3),
    _score(5, 1, 3),
    _score(5, 2, 3),
    _score(5, 7, 3),
    _score(5, 8, 3),
  ];
  H2hMember seat(int user, int slot, {int from = 1, int? until}) => H2hMember(
    userId: userNo(user),
    slot: slot,
    joinedAt: DateTime.utc(2026, 11, 1, 0, user),
    fromRound: from,
    untilRound: until,
  );
  H2hGroupSheet sheet(List<H2hMember> members) => H2hGroupSheet(
    members: members,
    scores: scores,
    settledRounds: const <int>{1, 2, 3, 4, 5, 6, 7, 8},
    voidRounds: const <int>{},
  );
  return H2hMonthBook.of(
    groups: const [
      H2hGroupRef(
        leagueId: _elite,
        division: H2hDivision.first,
        groupIndex: 0,
        capacity: 4,
      ),
      H2hGroupRef(
        leagueId: _extra,
        division: H2hDivision.second,
        groupIndex: 0,
        capacity: 4,
      ),
    ],
    sheets: {
      _elite: sheet([
        seat(1, 0, until: swapRound - 1),
        seat(5, 0, from: swapRound),
        seat(2, 1),
        seat(3, 2),
        seat(4, 3),
      ]),
      _extra: sheet([
        seat(5, 0, until: swapRound - 1),
        seat(1, 0, from: swapRound),
        seat(6, 1),
        seat(7, 2),
        seat(8, 3),
      ]),
    },
  );
}

void main() {
  group('H2hMonthBook.standings after a swap', () {
    test('from round 7 the seats trade their records', () {
      final book = _book(swapRound: 7);
      final month = book.standings(_rounds(8));

      // The elite seat: player 1's six wins (the opponents never predicted),
      // then player 5's two walkovers won with 3 points each.
      final five = month[userNo(5)]!;
      expect((five.won, five.drawn, five.lost), (8, 0, 0));
      expect(five.leaguePoints, 24);
      expect(five.pointsFor, 6 * 3 + 2 * 3);
      expect(five.exactCount, 8);
      // His own rounds are still his own, the matches behind the totals are
      // the seat's.
      expect([for (final m in five.matches) m.round], [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(five.counted, isNotNull);
      expect(
        [for (final m in five.countedMatches) m.round],
        [1, 2, 3, 4, 5, 6, 7, 8],
      );

      // The extra seat: player 5's two wins and four rounds without a
      // prediction, then player 1's two absent rounds.
      final one = month[userNo(1)]!;
      expect((one.won, one.drawn, one.lost), (2, 0, 6));
      expect(one.leaguePoints, 6);
      expect(one.pointsFor, 2 * 3);
      expect(one.played, 8);
    });

    test('a swap before round 7 keeps each player his own month', () {
      final book = _book(swapRound: 4);
      final month = book.standings(_rounds(8));

      // Player 1: three wins in the elite group, three in the extra one
      // (rounds 4 to 6, before round 7) and two absent rounds.
      final one = month[userNo(1)]!;
      expect((one.won, one.drawn, one.lost), (6, 0, 2));
      expect(one.counted, isNull);
      // Player 5: two wins and one absent round in the extra group, three
      // absent rounds and two walkovers won in the elite group.
      final five = month[userNo(5)]!;
      expect((five.won, five.drawn, five.lost), (4, 0, 4));
      expect(five.counted, isNull);
    });

    test('the elite table ranks the player who holds the seat now', () {
      final book = _book(swapRound: 7);
      final placings = book.placingsOf(_elite, _rounds(8));

      expect(placings.first.standing.userId, userNo(5));
      expect(placings.first.standing.leaguePoints, 24);
      expect(placings.map((p) => p.standing.userId).toSet(), {
        userNo(5),
        userNo(2),
        userNo(3),
        userNo(4),
      });
    });

    test('before round 7 is played nothing moves yet', () {
      // The swap is stored for round 7 while round 6 is the last one played:
      // the totals already follow the seats.
      final book = _book(swapRound: 7);
      final month = book.standings(_rounds(6));

      expect(month[userNo(5)]!.won, 6);
      expect(month[userNo(1)]!.won, 2);
      expect(month[userNo(1)]!.lost, 4);
    });

    test('with no round played every member is there with an empty month', () {
      final book = _book(swapRound: 7);
      final month = book.standings(const <H2hRoundRef>[]);

      expect(month[userNo(1)]!.played, 0);
      expect(month[userNo(5)]!.played, 0);
    });
  });
}
