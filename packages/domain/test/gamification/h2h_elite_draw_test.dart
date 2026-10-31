/// The elite draw (NK182, decided 2026-10-31): from November 2026 the
/// first 80 of the drawing order are dealt like a snake into four even
/// groups, and the rest go into extra groups of twenty in the same order,
/// the last one taking what is left and a single player left at the end
/// joining the group before him.
library;

import 'package:domain/domain.dart';
import 'package:test/test.dart';

List<UserId> _players(int count) => [
  for (var i = 0; i < count; i++)
    UserId('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
];

/// The 0-based positions in [order] of the players of [group].
List<int> _positions(H2hDrawGroup group, List<UserId> order) => [
  for (final seat in group.seats) order.indexOf(seat.userId),
];

void main() {
  group('H2hLeaguePolicy.eliteDraw', () {
    test('125 players: four elite groups of 20, then 20, 20 and 5', () {
      final order = _players(125);

      final groups = H2hLeaguePolicy.eliteDraw(order);

      expect(
        [for (final g in groups) (g.division, g.groupIndex, g.seats.length)],
        [
          (H2hDivision.first, 0, 20),
          (H2hDivision.first, 1, 20),
          (H2hDivision.first, 2, 20),
          (H2hDivision.first, 3, 20),
          (H2hDivision.second, 0, 20),
          (H2hDivision.second, 1, 20),
          (H2hDivision.second, 2, 5),
        ],
      );
      for (final g in groups) {
        expect(g.capacity, H2hLeaguePolicy.groupCapacity);
      }
    });

    test('the first 80 are dealt like a snake, so the groups are even', () {
      final order = _players(125);

      final groups = H2hLeaguePolicy.eliteDraw(order);

      expect(_positions(groups[0], order).sublist(0, 6), [0, 7, 8, 15, 16, 23]);
      expect(_positions(groups[1], order).sublist(0, 6), [1, 6, 9, 14, 17, 22]);
      expect(_positions(groups[2], order).sublist(0, 6), [
        2,
        5,
        10,
        13,
        18,
        21,
      ]);
      expect(_positions(groups[3], order).sublist(0, 6), [
        3,
        4,
        11,
        12,
        19,
        20,
      ]);
      // Every group holds one player of each band of four: the sums of the
      // places are equal.
      for (var g = 0; g < 4; g++) {
        final sum = _positions(groups[g], order).fold<int>(0, (a, b) => a + b);
        expect(sum, 790, reason: 'group $g');
        // The slot is the band the player came from.
        expect([
          for (final s in groups[g].seats) s.slot,
        ], List<int>.generate(20, (i) => i));
      }
    });

    test('the extra groups follow the order: 81st to 100th is group 5', () {
      final order = _players(125);

      final groups = H2hLeaguePolicy.eliteDraw(order);
      final extras = groups.sublist(4);

      expect(
        _positions(extras[0], order),
        List<int>.generate(20, (i) => 80 + i),
      );
      expect(
        _positions(extras[1], order),
        List<int>.generate(20, (i) => 100 + i),
      );
      expect(_positions(extras[2], order), [120, 121, 122, 123, 124]);
      expect([for (final s in extras[2].seats) s.slot], [0, 1, 2, 3, 4]);
    });

    test('a single player left at the end joins the last group (22 seats)', () {
      final order = _players(101);

      final groups = H2hLeaguePolicy.eliteDraw(order);

      expect(groups, hasLength(5));
      final last = groups.last;
      expect(last.division, H2hDivision.second);
      expect(last.groupIndex, 0);
      expect(last.seats, hasLength(21));
      expect(last.capacity, 22);
      expect(last.seats.last.userId, order[100]);
      expect(last.seats.last.slot, 20);
    });

    test('a single extra player with no group to join plays alone', () {
      final groups = H2hLeaguePolicy.eliteDraw(_players(81));

      expect(groups, hasLength(5));
      expect(groups.last.division, H2hDivision.second);
      expect(groups.last.seats, hasLength(1));
      expect(groups.last.capacity, H2hLeaguePolicy.groupCapacity);
    });

    test('fewer than 80: four elite groups as even as possible, no extra', () {
      final order = _players(45);

      final groups = H2hLeaguePolicy.eliteDraw(order);

      expect(
        [for (final g in groups) g.division],
        [
          H2hDivision.first,
          H2hDivision.first,
          H2hDivision.first,
          H2hDivision.first,
        ],
      );
      expect([for (final g in groups) g.seats.length], [11, 11, 11, 12]);
      expect(groups.first.seats.first.userId, order.first);
    });

    test('a handful of players never makes a group of one', () {
      expect(
        [
          for (final g in H2hLeaguePolicy.eliteDraw(_players(7)))
            g.seats.length,
        ],
        [3, 2, 2],
      );
      expect(
        [
          for (final g in H2hLeaguePolicy.eliteDraw(_players(3)))
            g.seats.length,
        ],
        [3],
      );
      expect(H2hLeaguePolicy.eliteDraw(const <UserId>[]), isEmpty);
    });
  });

  group('the elite months', () {
    test('November 2026 and every month after it use the elite draw', () {
      expect(H2hLeaguePolicy.usesEliteDraw(DateTime.utc(2026, 10)), isFalse);
      expect(
        H2hLeaguePolicy.usesEliteDraw(DateTime.utc(2026, 10, 31)),
        isFalse,
      );
      expect(H2hLeaguePolicy.usesEliteDraw(DateTime.utc(2026, 11)), isTrue);
      expect(H2hLeaguePolicy.usesEliteDraw(DateTime.utc(2026, 12, 15)), isTrue);
      expect(H2hLeaguePolicy.usesEliteDraw(DateTime.utc(2027, 1)), isTrue);
    });

    test('group numbers: 1 to 4 for the elite groups, 5 and up after', () {
      expect(
        H2hLeaguePolicy.groupNumberOf(
          division: H2hDivision.first,
          groupIndex: 0,
        ),
        1,
      );
      expect(
        H2hLeaguePolicy.groupNumberOf(
          division: H2hDivision.first,
          groupIndex: 3,
        ),
        4,
      );
      expect(
        H2hLeaguePolicy.groupNumberOf(
          division: H2hDivision.second,
          groupIndex: 0,
        ),
        5,
      );
      expect(
        H2hLeaguePolicy.groupNumberOf(
          division: H2hDivision.second,
          groupIndex: 2,
        ),
        7,
      );
    });

    test('the cup places: three of an elite group, none of an extra one', () {
      expect(H2hLeaguePolicy.cupZoneOf(H2hDivision.first, 20), 3);
      expect(H2hLeaguePolicy.cupZoneOf(H2hDivision.first, 2), 2);
      expect(H2hLeaguePolicy.cupZoneOf(H2hDivision.second, 20), 0);
    });

    test('a group added to an elite month is the next extra group', () {
      final added = H2hLeaguePolicy.extend(
        existing: const [
          (division: H2hDivision.first, groupIndex: 0),
          (division: H2hDivision.first, groupIndex: 1),
          (division: H2hDivision.first, groupIndex: 2),
          (division: H2hDivision.first, groupIndex: 3),
          (division: H2hDivision.second, groupIndex: 0),
          (division: H2hDivision.second, groupIndex: 1),
        ],
        order: _players(25),
        groups: 5,
        elite: true,
      );

      expect(
        [for (final g in added) g.division],
        [H2hDivision.second, H2hDivision.second],
      );
      expect([for (final g in added) g.groupIndex], [2, 3]);
      expect([for (final g in added) g.seats.length], [20, 5]);
    });
  });
}
