/// The Elite Cup's rules (NK185, decided 2026-10-31): three separate paths,
/// each a semi-final drawn at random and a final, played one after the
/// other; a pair is judged on the stage's fixtures only.
library;

import 'dart:math';

import 'package:domain/domain.dart';
import 'package:test/test.dart';

UserId _u(int i) =>
    UserId('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}');

H2hCupEntry _entry(
  int user, {
  int place = 1,
  int group = 1,
  int league = 30,
  int points = 100,
  int exact = 5,
}) => H2hCupEntry(
  userId: _u(user),
  place: place,
  groupNumber: group,
  leaguePoints: league,
  pointsFor: points,
  exactCount: exact,
);

H2hCupSide _side(int points, {int exact = 0, int predicted = 6}) =>
    H2hCupSide(points: points, exact: exact, predicted: predicted);

void main() {
  group('the order', () {
    test('path 1 semi and final, then path 2, then path 3: days 20 to 25', () {
      expect(
        [for (final s in H2hCupPolicy.order) '${s.place}${s.round.wire}'],
        ['1semi', '1final', '2semi', '2final', '3semi', '3final'],
      );
      expect(
        [for (final s in H2hCupPolicy.order) s.expectedDay],
        [20, 21, 22, 23, 24, 25],
      );
    });

    test('the league is finished only with 19 rounds judged', () {
      expect(
        H2hCupPolicy.leagueFinished(roundCount: 19, judgedRounds: 19),
        isTrue,
      );
      expect(
        H2hCupPolicy.leagueFinished(roundCount: 19, judgedRounds: 18),
        isFalse,
      );
      expect(
        H2hCupPolicy.leagueFinished(roundCount: 18, judgedRounds: 18),
        isFalse,
      );
    });

    test('the stored round names', () {
      expect(H2hCupRound.fromWire('semi'), H2hCupRound.semi);
      expect(H2hCupRound.fromWire('final'), H2hCupRound.finale);
      expect(H2hCupRound.fromWire('quarter'), isNull);
    });
  });

  group('drawSemis', () {
    final four = [_entry(1), _entry(2), _entry(3), _entry(4)];

    test('four players make two pairs, each player once', () {
      final pairs = H2hCupPolicy.drawSemis(four, Random(7));

      expect(pairs, hasLength(2));
      expect([for (final p in pairs) p.slot], [1, 2]);
      expect(
        {
          for (final p in pairs) ...[p.home, p.away],
        },
        {_u(1), _u(2), _u(3), _u(4)},
      );
      expect(H2hCupPolicy.byeOf(four, pairs), isNull);
    });

    test('the draw is random: another seed, other pairs', () {
      final seen = <String>{};
      for (var seed = 0; seed < 20; seed++) {
        final pairs = H2hCupPolicy.drawSemis(four, Random(seed));
        final first = {pairs.first.home, pairs.first.away};
        seen.add(
          first.contains(_u(1))
              ? 'with ${first.firstWhere((u) => u != _u(1)).value}'
              : 'other',
        );
      }
      expect(seen.length, greaterThan(1));
    });

    test('three players: one pair and a bye; two: one pair; one: none', () {
      final three = four.sublist(0, 3);
      final pairs = H2hCupPolicy.drawSemis(three, Random(1));
      expect(pairs, hasLength(1));
      expect(H2hCupPolicy.byeOf(three, pairs), isNotNull);

      expect(
        H2hCupPolicy.drawSemis(four.sublist(0, 2), Random(1)),
        hasLength(1),
      );
      expect(H2hCupPolicy.drawSemis(four.sublist(0, 1), Random(1)), isEmpty);
    });
  });

  group('decide', () {
    final a = _entry(1, league: 40, group: 2);
    final b = _entry(2, league: 38, group: 1);

    test('the higher points win', () {
      final d = H2hCupPolicy.decide(
        home: _side(9),
        away: _side(12),
        homeEntry: a,
        awayEntry: b,
      );
      expect(d.winner, _u(2));
      expect(d.outcome, H2hCupOutcome.points);
    });

    test('level on points: more exact scorelines', () {
      final d = H2hCupPolicy.decide(
        home: _side(10, exact: 2),
        away: _side(10, exact: 1),
        homeEntry: a,
        awayEntry: b,
      );
      expect(d.winner, _u(1));
      expect(d.outcome, H2hCupOutcome.exact);
    });

    test('level on both: the better league month', () {
      final d = H2hCupPolicy.decide(
        home: _side(10, exact: 1),
        away: _side(10, exact: 1),
        homeEntry: b,
        awayEntry: a,
      );
      expect(d.winner, _u(1));
      expect(d.outcome, H2hCupOutcome.league);
    });

    test('the side that predicted beats the side that did not, even with '
        'zero points', () {
      final d = H2hCupPolicy.decide(
        home: H2hCupSide.absent,
        away: _side(0),
        homeEntry: a,
        awayEntry: b,
      );
      expect(d.winner, _u(2));
      expect(d.outcome, H2hCupOutcome.walkover);
    });

    test('neither predicted: both lose', () {
      final d = H2hCupPolicy.decide(
        home: H2hCupSide.absent,
        away: H2hCupSide.absent,
        homeEntry: a,
        awayEntry: b,
      );
      expect(d.winner, isNull);
      expect(d.outcome, H2hCupOutcome.bothAbsent);
    });

    test('the league tie-break: league points, points, exact, group', () {
      expect(
        H2hCupPolicy.compareLeague(_entry(1, league: 41), _entry(2)),
        lessThan(0),
      );
      expect(
        H2hCupPolicy.compareLeague(_entry(1, points: 99), _entry(2)),
        greaterThan(0),
      );
      expect(
        H2hCupPolicy.compareLeague(_entry(1, exact: 6), _entry(2)),
        lessThan(0),
      );
      expect(
        H2hCupPolicy.compareLeague(_entry(1, group: 3), _entry(2, group: 2)),
        greaterThan(0),
      );
    });
  });
}
