import 'package:domain/domain.dart';
import 'package:test/test.dart';

WeeklyLeagueEntry _entry(
  String id, {
  int points = 0,
  int exact = 0,
  int decided = 0,
  int seatMinute = 0,
}) => WeeklyLeagueEntry(
  userId: UserId(id),
  points: points,
  exactCount: exact,
  decidedCount: decided,
  joinedAt: DateTime.utc(2026, 9, 21).add(Duration(minutes: seatMinute)),
);

void main() {
  group('WeeklyLeaguePolicy.weekStartOf', () {
    test('a Monday opens its own week', () {
      // 2026-09-21 is a Monday.
      expect(
        WeeklyLeaguePolicy.weekStartOf(DateTime.utc(2026, 9, 21)),
        DateTime.utc(2026, 9, 21),
      );
    });

    test('a Sunday belongs to the week that opened six days earlier', () {
      expect(
        WeeklyLeaguePolicy.weekStartOf(DateTime.utc(2026, 9, 27)),
        DateTime.utc(2026, 9, 21),
      );
    });

    test('the next Monday opens the next week', () {
      expect(
        WeeklyLeaguePolicy.weekStartOf(DateTime.utc(2026, 9, 28)),
        DateTime.utc(2026, 9, 28),
      );
    });

    test('the week end is the exclusive next Monday', () {
      expect(
        WeeklyLeaguePolicy.weekEndOf(DateTime.utc(2026, 9, 23)),
        DateTime.utc(2026, 9, 28),
      );
    });

    test('containment covers Monday through Sunday and stops', () {
      final start = DateTime.utc(2026, 9, 21);
      expect(WeeklyLeaguePolicy.weekContains(start, start), isTrue);
      expect(
        WeeklyLeaguePolicy.weekContains(start, DateTime.utc(2026, 9, 27)),
        isTrue,
      );
      expect(
        WeeklyLeaguePolicy.weekContains(start, DateTime.utc(2026, 9, 28)),
        isFalse,
      );
      expect(
        WeeklyLeaguePolicy.weekContains(start, DateTime.utc(2026, 9, 20)),
        isFalse,
      );
    });
  });

  group('WeeklyLeaguePolicy.movementCount', () {
    test('is proportional and capped at five', () {
      expect(WeeklyLeaguePolicy.movementCount(20), 5);
      expect(WeeklyLeaguePolicy.movementCount(40), 5);
      expect(WeeklyLeaguePolicy.movementCount(16), 4);
      expect(WeeklyLeaguePolicy.movementCount(8), 2);
      expect(WeeklyLeaguePolicy.movementCount(4), 1);
      expect(WeeklyLeaguePolicy.movementCount(3), 0);
      expect(WeeklyLeaguePolicy.movementCount(0), 0);
    });
  });

  group('WeeklyLeaguePolicy.order', () {
    test('ranks by points, then exact, then fewer decided, then seat', () {
      final ordered = WeeklyLeaguePolicy.order(<WeeklyLeagueEntry>[
        _entry('late', points: 9, exact: 2, decided: 5, seatMinute: 10),
        _entry('early', points: 9, exact: 2, decided: 5, seatMinute: 1),
        _entry('fewer', points: 9, exact: 2, decided: 4, seatMinute: 20),
        _entry('exact', points: 9, exact: 3, decided: 9, seatMinute: 30),
        _entry('top', points: 12),
      ]);
      expect(ordered.map((e) => e.userId.value).toList(), <String>[
        'top',
        'exact',
        'fewer',
        'early',
        'late',
      ]);
    });

    test('leaves the caller list untouched', () {
      final input = <WeeklyLeagueEntry>[
        _entry('b', points: 1),
        _entry('a', points: 5),
      ];
      WeeklyLeaguePolicy.order(input);
      expect(input.first.userId.value, 'b');
    });
  });

  group('WeeklyLeaguePolicy.judge', () {
    test('promotes the top five and relegates the bottom five of twenty', () {
      final entries = <WeeklyLeagueEntry>[
        for (var i = 0; i < 20; i++)
          _entry('u$i', points: 100 - i, seatMinute: i),
      ];
      final placings = WeeklyLeaguePolicy.judge(
        tier: WeeklyLeagueTier.gold,
        entries: entries,
      );

      expect(placings.length, 20);
      expect(placings.first.rank, 1);
      expect(placings.last.rank, 20);
      expect(
        placings.where((p) => p.outcome == WeeklyLeagueOutcome.promoted).length,
        5,
      );
      expect(
        placings
            .where((p) => p.outcome == WeeklyLeagueOutcome.relegated)
            .length,
        5,
      );
      expect(placings[5].outcome, WeeklyLeagueOutcome.held);
      expect(placings[14].outcome, WeeklyLeagueOutcome.held);
    });

    test('bronze relegates nobody', () {
      final entries = <WeeklyLeagueEntry>[
        for (var i = 0; i < 20; i++)
          _entry('u$i', points: 100 - i, seatMinute: i),
      ];
      final placings = WeeklyLeaguePolicy.judge(
        tier: WeeklyLeagueTier.bronze,
        entries: entries,
      );
      expect(
        placings.any((p) => p.outcome == WeeklyLeagueOutcome.relegated),
        isFalse,
      );
      expect(
        placings.where((p) => p.outcome == WeeklyLeagueOutcome.promoted).length,
        5,
      );
    });

    test('elite promotes nobody', () {
      final entries = <WeeklyLeagueEntry>[
        for (var i = 0; i < 20; i++)
          _entry('u$i', points: 100 - i, seatMinute: i),
      ];
      final placings = WeeklyLeaguePolicy.judge(
        tier: WeeklyLeagueTier.elite,
        entries: entries,
      );
      expect(
        placings.any((p) => p.outcome == WeeklyLeagueOutcome.promoted),
        isFalse,
      );
      expect(
        placings
            .where((p) => p.outcome == WeeklyLeagueOutcome.relegated)
            .length,
        5,
      );
    });

    test('a member who scored nothing is never promoted', () {
      final entries = <WeeklyLeagueEntry>[
        for (var i = 0; i < 8; i++) _entry('u$i', seatMinute: i),
      ];
      final placings = WeeklyLeaguePolicy.judge(
        tier: WeeklyLeagueTier.silver,
        entries: entries,
      );
      expect(
        placings.any((p) => p.outcome == WeeklyLeagueOutcome.promoted),
        isFalse,
      );
      // The bottom two still fall: an unplayed week is not a defence.
      expect(
        placings
            .where((p) => p.outcome == WeeklyLeagueOutcome.relegated)
            .length,
        2,
      );
    });

    test('a group too small to move anyone only places', () {
      final placings = WeeklyLeaguePolicy.judge(
        tier: WeeklyLeagueTier.silver,
        entries: <WeeklyLeagueEntry>[
          _entry('a', points: 5),
          _entry('b', points: 3, seatMinute: 1),
          _entry('c', points: 1, seatMinute: 2),
        ],
      );
      expect(placings.map((p) => p.rank).toList(), <int>[1, 2, 3]);
      expect(
        placings.every((p) => p.outcome == WeeklyLeagueOutcome.held),
        isTrue,
      );
    });

    test('an empty group judges to nothing', () {
      expect(
        WeeklyLeaguePolicy.judge(
          tier: WeeklyLeagueTier.gold,
          entries: const <WeeklyLeagueEntry>[],
        ),
        isEmpty,
      );
    });
  });

  group('WeeklyLeagueTier', () {
    test('maps to and from the stored level', () {
      for (final tier in WeeklyLeagueTier.values) {
        expect(WeeklyLeagueTier.ofLevel(tier.level), tier);
      }
      expect(WeeklyLeagueTier.ofLevel(0), isNull);
      expect(WeeklyLeagueTier.ofLevel(6), isNull);
    });

    test('the ladder does not run off either end', () {
      expect(WeeklyLeagueTier.bronze.below, WeeklyLeagueTier.bronze);
      expect(WeeklyLeagueTier.elite.above, WeeklyLeagueTier.elite);
      expect(WeeklyLeagueTier.gold.above, WeeklyLeagueTier.platinum);
      expect(WeeklyLeagueTier.gold.below, WeeklyLeagueTier.silver);
    });

    test('nextTier follows the outcome', () {
      expect(
        WeeklyLeaguePolicy.nextTier(
          WeeklyLeagueTier.silver,
          WeeklyLeagueOutcome.promoted,
        ),
        WeeklyLeagueTier.gold,
      );
      expect(
        WeeklyLeaguePolicy.nextTier(
          WeeklyLeagueTier.silver,
          WeeklyLeagueOutcome.relegated,
        ),
        WeeklyLeagueTier.bronze,
      );
      expect(
        WeeklyLeaguePolicy.nextTier(
          WeeklyLeagueTier.silver,
          WeeklyLeagueOutcome.held,
        ),
        WeeklyLeagueTier.silver,
      );
    });
  });
}
