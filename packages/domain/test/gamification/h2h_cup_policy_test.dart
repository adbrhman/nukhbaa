/// The Elite Cup's rules (NK185, decided 2026-10-31): three separate paths,
/// each a semi-final drawn at random and a final, played on four days, paths
/// 2 and 3 side by side (NK276); a pair is judged on the stage's fixtures
/// only.
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

H2hCupSide _side(
  int points, {
  int exact = 0,
  int predicted = 6,
  int direction = 0,
}) => H2hCupSide(
  points: points,
  exact: exact,
  predicted: predicted,
  direction: direction,
);

void main() {
  group('the order', () {
    // NK276: four days, paths 2 and 3 side by side (owner, 2026-11-14).
    test('path 1 semi and final, then paths 2 and 3 together: days 20 to '
        '23', () {
      expect(
        [for (final s in H2hCupPolicy.order) '${s.place}${s.round.wire}'],
        ['1semi', '1final', '2semi', '3semi', '2final', '3final'],
      );
      expect(
        [for (final s in H2hCupPolicy.order) s.expectedDay],
        [20, 21, 22, 22, 23, 23],
      );
      expect(
        [
          for (final day in H2hCupPolicy.days)
            [for (final s in day) '${s.place}${s.round.wire}'],
        ],
        [
          ['1semi'],
          ['1final'],
          ['2semi', '3semi'],
          ['2final', '3final'],
        ],
      );
    });

    test('every step sits on its own cup day, and the order follows the '
        'days', () {
      for (var i = 0; i < H2hCupPolicy.days.length; i++) {
        for (final s in H2hCupPolicy.days[i]) {
          expect(s.cupDay, i + 1, reason: '$s');
        }
      }
      expect(H2hCupPolicy.order, [for (final day in H2hCupPolicy.days) ...day]);
      expect({
        for (final s in H2hCupPolicy.order) s.place,
      }, H2hCupPolicy.places.toSet());
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
      expect(H2hCupRound.fromWire('round16'), H2hCupRound.round16);
      expect(H2hCupRound.fromWire('quarter'), H2hCupRound.quarter);
      expect(H2hCupRound.fromWire('round32'), isNull);
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

  // NK357_01h
  group('the bracket', () {
    // Owner decision 2026-11-28: one bracket of sixteen, a round a day.
    test('four days, one round each, on path 1: days 20 to 23', () {
      expect(
        [
          for (final day in H2hCupPolicy.bracketDays)
            [for (final s in day) '${s.place}${s.round.wire}'],
        ],
        [
          ['1round16'],
          ['1quarter'],
          ['1semi'],
          ['1final'],
        ],
      );
      for (var i = 0; i < H2hCupPolicy.bracketDays.length; i++) {
        final s = H2hCupPolicy.bracketDays[i].single;
        expect(s.cupDay, i + 1, reason: '$s');
        expect(s.expectedDay, 20 + i, reason: '$s');
        expect(s.inBracket, isTrue, reason: '$s');
      }
    });

    test('a bracket semi-final is not the old path semi-final', () {
      const old = H2hCupStep(1, H2hCupRound.semi);
      const inBracket = H2hCupStep(1, H2hCupRound.semi, bracket: true);
      expect(old.cupDay, 1);
      expect(inBracket.cupDay, 3);
      expect(old == inBracket, isFalse);
      expect(const H2hCupStep(1, H2hCupRound.finale).cupDay, 2);
      expect(const H2hCupStep(1, H2hCupRound.finale, bracket: true).cupDay, 4);
      // A round only the bracket has needs no flag.
      expect(
        const H2hCupStep(1, H2hCupRound.round16),
        const H2hCupStep(1, H2hCupRound.round16, bracket: true),
      );
      expect(const H2hCupStep(1, H2hCupRound.quarter).cupDay, 2);
    });

    test('only December 2026 on is a bracket; November keeps the paths', () {
      final november = DateTime.utc(2026, 11);
      final december = DateTime.utc(2026, 12);
      expect(H2hCupPolicy.isBracket(november), isFalse);
      expect(H2hCupPolicy.isBracket(december), isTrue);
      expect(H2hCupPolicy.isBracket(DateTime.utc(2027)), isTrue);
      expect(H2hCupPolicy.titleCountOf(november), 3);
      expect(H2hCupPolicy.titleCountOf(december), 1);
      expect(H2hCupPolicy.daysOf(november), H2hCupPolicy.days);
      expect(H2hCupPolicy.daysOf(december), H2hCupPolicy.bracketDays);
      expect(H2hCupPolicy.bracketSize, 16);
    });

    test('the round follows the number of players left', () {
      expect(
        [
          for (final n in [16, 9, 8, 5, 4, 3, 2]) H2hCupPolicy.roundFor(n),
        ],
        [
          H2hCupRound.round16,
          H2hCupRound.round16,
          H2hCupRound.quarter,
          H2hCupRound.quarter,
          H2hCupRound.semi,
          H2hCupRound.semi,
          H2hCupRound.finale,
        ],
      );
      expect(H2hCupPolicy.roundFor(1), isNull);
      expect(H2hCupPolicy.roundFor(0), isNull);
    });
  });

  group('drawBracket', () {
    // Eight groups with a first and a second place each: users 1 to 8 are
    // the firsts and users 11 to 18 the seconds of groups 1 to 8.
    List<H2hCupEntry> sixteen() => [
      for (var g = 1; g <= 8; g++) _entry(g, place: 1, group: g),
      for (var g = 1; g <= 8; g++) _entry(10 + g, place: 2, group: g),
    ];

    test('every first meets a second of another group, whatever the seed', () {
      final entries = sixteen();
      final byUser = {for (final e in entries) e.userId: e};
      for (var seed = 0; seed < 300; seed++) {
        final pairs = H2hCupPolicy.drawBracket(entries, Random(seed));
        expect(pairs, hasLength(8), reason: 'seed $seed');
        expect([for (final p in pairs) p.slot], [1, 2, 3, 4, 5, 6, 7, 8]);
        final seen = <UserId>{};
        for (final p in pairs) {
          final home = byUser[p.home]!;
          final away = byUser[p.away]!;
          expect(home.place, 1, reason: 'seed $seed');
          expect(away.place, 2, reason: 'seed $seed');
          expect(
            home.groupNumber == away.groupNumber,
            isFalse,
            reason: 'seed $seed',
          );
          seen
            ..add(p.home)
            ..add(p.away);
        }
        expect(seen, hasLength(16), reason: 'seed $seed');
        expect(H2hCupPolicy.byeOf(entries, pairs), isNull);
      }
    });

    test('the draw is random: other seeds, other pairs', () {
      final entries = sixteen();
      final drawn = <String>{
        for (var seed = 0; seed < 20; seed++)
          [
            for (final p in H2hCupPolicy.drawBracket(entries, Random(seed)))
              '${p.home.value}-${p.away.value}',
          ].join(','),
      };
      expect(drawn.length, greaterThan(1));
    });

    test('a group with no second place leaves one over: the bye', () {
      final entries = [
        for (var g = 1; g <= 8; g++) _entry(g, place: 1, group: g),
        for (var g = 1; g <= 7; g++) _entry(10 + g, place: 2, group: g),
      ];
      final byUser = {for (final e in entries) e.userId: e};
      for (var seed = 0; seed < 100; seed++) {
        final pairs = H2hCupPolicy.drawBracket(entries, Random(seed));
        expect(pairs, hasLength(7), reason: 'seed $seed');
        for (final p in pairs) {
          expect(
            byUser[p.home]!.groupNumber == byUser[p.away]!.groupNumber,
            isFalse,
            reason: 'seed $seed',
          );
        }
        expect(
          H2hCupPolicy.byeOf(entries, pairs),
          isNotNull,
          reason: 'seed $seed',
        );
      }
    });

    test('one group alone still gets a draw, without a throw', () {
      final pairs = H2hCupPolicy.drawBracket([
        _entry(1, place: 1, group: 1),
        _entry(2, place: 2, group: 1),
      ], Random(1));
      expect(pairs, hasLength(1));
    });

    test('later rounds pair the survivors in slot order', () {
      final four = [for (var i = 1; i <= 4; i++) _u(i)];
      final pairs = H2hCupPolicy.pairsOf(four);
      expect([for (final p in pairs) p.slot], [1, 2]);
      expect(pairs[0].home, _u(1));
      expect(pairs[0].away, _u(2));
      expect(pairs[1].home, _u(3));
      expect(pairs[1].away, _u(4));
      expect(H2hCupPolicy.pairsOf([_u(1), _u(2), _u(3)]), hasLength(1));
      expect(H2hCupPolicy.pairsOf([_u(1)]), isEmpty);
      expect(H2hCupPolicy.pairsOf(const <UserId>[]), isEmpty);
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

    // NK305_02
    test('level on both: the month\'s prediction points beat the league '
        'points (the 2026-11-23 semi-final)', () {
      final d = H2hCupPolicy.decide(
        home: _side(3, exact: 1),
        away: _side(3, exact: 1),
        homeEntry: _entry(1, league: 34, points: 126, exact: 37, group: 2),
        awayEntry: _entry(2, league: 43, points: 123, exact: 41, group: 4),
      );
      expect(d.winner, _u(1));
      expect(d.outcome, H2hCupOutcome.league);
    });

    // NK319_02
    test('level on points and exact: more right directions win before the '
        'month (the 2026-11-24 final)', () {
      final d = H2hCupPolicy.decide(
        home: _side(3, exact: 1, predicted: 11, direction: 7),
        away: _side(3, exact: 1, predicted: 11, direction: 6),
        homeEntry: _entry(1, league: 30, points: 120, exact: 30, group: 2),
        awayEntry: _entry(2, league: 40, points: 130, exact: 40, group: 1),
      );
      expect(d.winner, _u(1));
      expect(d.outcome, H2hCupOutcome.direction);
    });

    // NK319_03
    test('level on directions too: the month decides, as before', () {
      final d = H2hCupPolicy.decide(
        home: _side(3, exact: 1, direction: 1),
        away: _side(3, exact: 1, direction: 1),
        homeEntry: _entry(1, league: 34, points: 126, exact: 37, group: 2),
        awayEntry: _entry(2, league: 43, points: 123, exact: 41, group: 4),
      );
      expect(d.winner, _u(1));
      expect(d.outcome, H2hCupOutcome.league);
    });

    // NK319_04
    test('points and exact scorelines still come before directions', () {
      final byPoints = H2hCupPolicy.decide(
        home: _side(9),
        away: _side(6, direction: 5),
        homeEntry: _entry(1),
        awayEntry: _entry(2),
      );
      expect(byPoints.winner, _u(1));
      expect(byPoints.outcome, H2hCupOutcome.points);
      final byExact = H2hCupPolicy.decide(
        home: _side(6, exact: 1),
        away: _side(6, direction: 5),
        homeEntry: _entry(1),
        awayEntry: _entry(2),
      );
      expect(byExact.winner, _u(1));
      expect(byExact.outcome, H2hCupOutcome.exact);
    });

    test('the league tie-break: points, exact, league points, group', () {
      expect(
        H2hCupPolicy.compareLeague(_entry(1, points: 101), _entry(2)),
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
        H2hCupPolicy.compareLeague(_entry(1, league: 41), _entry(2)),
        lessThan(0),
      );
      expect(
        H2hCupPolicy.compareLeague(_entry(1, group: 3), _entry(2, group: 2)),
        greaterThan(0),
      );
    });

    test(
      'the order of the tie-break: points over exact over league points',
      () {
        expect(
          H2hCupPolicy.compareLeague(
            _entry(1, league: 10, points: 101, exact: 1),
            _entry(2, league: 50, exact: 9),
          ),
          lessThan(0),
        );
        expect(
          H2hCupPolicy.compareLeague(
            _entry(1, league: 10, exact: 6),
            _entry(2, league: 50),
          ),
          lessThan(0),
        );
      },
    );
  });
}
