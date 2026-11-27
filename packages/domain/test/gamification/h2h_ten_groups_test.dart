/// Script 351: from December 2026 the draw opens ten even groups of twenty,
/// every player in the first division; November 2026 keeps its four.
library;

import 'package:domain/domain.dart';
import 'package:test/test.dart';

// NK351_02
List<UserId> _players(int count) => [
  for (var i = 0; i < count; i++)
    UserId('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
];

void main() {
  group('eliteDraw with ten groups', () {
    test('206 players: ten groups of 20, then the six left', () {
      final order = _players(206);

      final groups = H2hLeaguePolicy.eliteDraw(
        order,
        eliteGroupCount: H2hLeaguePolicy.fairGroups,
      );

      expect(
        [for (final g in groups) (g.division, g.groupIndex, g.seats.length)],
        [
          for (var i = 0; i < 10; i++) (H2hDivision.first, i, 20),
          (H2hDivision.second, 0, 6),
        ],
      );
      expect(groups.last.waiting, isFalse);
    });

    test('the six left wait for the twentieth from December on', () {
      final groups = H2hLeaguePolicy.eliteDraw(
        _players(206),
        waitingRest: true,
        eliteGroupCount: H2hLeaguePolicy.fairGroups,
      );

      expect(groups.last.division, H2hDivision.second);
      expect(groups.last.seats, hasLength(6));
      expect(groups.last.waiting, isTrue);
      expect(groups.last.capacity, H2hLeaguePolicy.groupCapacity);
    });

    test('the snake gives every group one player of each band of ten', () {
      final order = _players(206);

      final groups = H2hLeaguePolicy.eliteDraw(
        order,
        eliteGroupCount: H2hLeaguePolicy.fairGroups,
      );

      final sums = <int>[];
      for (final g in groups.take(10)) {
        expect(
          [for (final seat in g.seats) seat.slot],
          [for (var band = 0; band < 20; band++) band],
        );
        sums.add(
          g.seats.fold<int>(0, (sum, s) => sum + order.indexOf(s.userId)),
        );
      }
      expect(sums.toSet(), hasLength(1), reason: '$sums');
    });

    test('every player is seated once', () {
      final groups = H2hLeaguePolicy.eliteDraw(
        _players(206),
        eliteGroupCount: H2hLeaguePolicy.fairGroups,
      );

      final seated = [
        for (final g in groups)
          for (final seat in g.seats) seat.userId,
      ];
      expect(seated, hasLength(206));
      expect(seated.toSet(), hasLength(206));
    });

    test('150 players share the ten groups evenly, with no extra group', () {
      final groups = H2hLeaguePolicy.eliteDraw(
        _players(150),
        eliteGroupCount: H2hLeaguePolicy.fairGroups,
      );

      expect(groups, hasLength(10));
      for (final g in groups) {
        expect(g.division, H2hDivision.first);
        expect(g.seats, hasLength(15));
        expect(g.capacity, H2hLeaguePolicy.groupCapacity);
      }
    });

    test('without the count, the draw still opens the four of November', () {
      final groups = H2hLeaguePolicy.eliteDraw(_players(206));

      expect(
        groups.where((g) => g.division == H2hDivision.first),
        hasLength(4),
      );
    });
  });

  group('the ten groups by month', () {
    test('November 2026 has four elite groups, December on has ten', () {
      expect(H2hLeaguePolicy.eliteGroupsOf(DateTime.utc(2026, 11)), 4);
      expect(H2hLeaguePolicy.eliteGroupsOf(DateTime.utc(2026, 11, 30)), 4);
      expect(H2hLeaguePolicy.eliteGroupsOf(DateTime.utc(2026, 12)), 10);
      expect(H2hLeaguePolicy.eliteGroupsOf(DateTime.utc(2027, 1)), 10);
      expect(H2hLeaguePolicy.fairSeats, 200);
    });

    test('the group number a player sees follows the month', () {
      expect(
        H2hLeaguePolicy.groupNumberOf(
          division: H2hDivision.first,
          groupIndex: 9,
          eliteGroupCount: H2hLeaguePolicy.fairGroups,
        ),
        10,
      );
      expect(
        H2hLeaguePolicy.groupNumberOf(
          division: H2hDivision.second,
          groupIndex: 0,
          eliteGroupCount: H2hLeaguePolicy.fairGroups,
        ),
        11,
      );
      expect(
        H2hLeaguePolicy.groupNumberOf(
          division: H2hDivision.second,
          groupIndex: 0,
        ),
        5,
      );
    });

    test('the group below, with ten groups and with four', () {
      const ten = H2hLeaguePolicy.fairGroups;
      expect(H2hAbsencePolicy.groupBelow(3, eliteGroupCount: ten), 11);
      expect(H2hAbsencePolicy.groupBelow(10, eliteGroupCount: ten), 11);
      expect(H2hAbsencePolicy.groupBelow(11, eliteGroupCount: ten), 12);
      expect(H2hAbsencePolicy.groupBelow(4), 5);
      expect(H2hAbsencePolicy.groupBelow(5), 6);
    });
  });
}
