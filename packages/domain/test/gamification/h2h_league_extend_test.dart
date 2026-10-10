/// Groups added to a month already drawn (2026-10-11): twenty at a time,
/// in the order given, into the next empty division of the ladder, then
/// the open division after its last group.
library;

import 'package:domain/domain.dart';
import 'package:test/test.dart';

List<UserId> _players(int count) => [
  for (var i = 0; i < count; i++)
    UserId('00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}'),
];

void main() {
  test('after the first division: the second, the third, the open', () {
    final order = _players(72);

    final added = H2hLeaguePolicy.extend(
      existing: const [(division: H2hDivision.first, groupIndex: 0)],
      order: order,
      groups: 3,
    );

    expect(added, hasLength(3));
    expect(
      [for (final g in added) (g.division, g.groupIndex)],
      [
        (H2hDivision.second, 0),
        (H2hDivision.third, 0),
        (H2hDivision.fourth, 0),
      ],
    );
    for (final g in added) {
      expect(g.seats, hasLength(H2hLeaguePolicy.groupCapacity));
      expect([for (final s in g.seats) s.slot], List.generate(20, (i) => i));
    }
    expect(added[0].seats.first.userId, order[0]);
    expect(added[1].seats.first.userId, order[20]);
    expect(added[2].seats.last.userId, order[59]);
  });

  test('the open division grows after its last group', () {
    final added = H2hLeaguePolicy.extend(
      existing: const [
        (division: H2hDivision.first, groupIndex: 0),
        (division: H2hDivision.second, groupIndex: 0),
        (division: H2hDivision.third, groupIndex: 0),
        (division: H2hDivision.fourth, groupIndex: 0),
        (division: H2hDivision.fourth, groupIndex: 1),
      ],
      order: _players(25),
      groups: 5,
    );

    expect(
      [for (final g in added) g.division],
      [H2hDivision.fourth, H2hDivision.fourth],
    );
    expect([for (final g in added) g.groupIndex], [2, 3]);
    expect([for (final g in added) g.seats.length], [20, 5]);
  });

  test('a single player left at the end waits', () {
    final added = H2hLeaguePolicy.extend(
      existing: const [],
      order: _players(21),
      groups: 3,
    );

    expect(added, hasLength(1));
    expect(added.single.division, H2hDivision.first);
    expect(added.single.seats, hasLength(20));
  });

  test('nobody waiting, or no group asked for, adds nothing', () {
    expect(
      H2hLeaguePolicy.extend(existing: const [], order: _players(1), groups: 2),
      isEmpty,
    );
    expect(
      H2hLeaguePolicy.extend(
        existing: const [],
        order: _players(40),
        groups: 0,
      ),
      isEmpty,
    );
  });
}
