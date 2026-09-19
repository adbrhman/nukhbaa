import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('StreakTally.fromMatchDays', () {
    test('counts the run back from the most recent match day', () {
      final tally = StreakTally.fromMatchDays(<bool>[
        true,
        true,
        true,
        false,
        true,
      ]);

      expect(tally.current, 3);
    });

    test('one missed match day ends the run at once', () {
      // No freeze and no grace (decided 2026-09-19).
      final tally = StreakTally.fromMatchDays(<bool>[
        false,
        true,
        true,
        true,
        true,
      ]);

      expect(tally.current, 0);
      expect(tally.longest, 4);
    });

    test('an unfinished today is skipped, not counted as a miss', () {
      final tally = StreakTally.fromMatchDays(<bool>[
        false,
        true,
        true,
      ], newestIsPendingToday: true);

      expect(tally.current, 2);
    });

    test('an earlier incomplete day still breaks the run', () {
      // The skip applies to today alone; yesterday is a real miss.
      final tally = StreakTally.fromMatchDays(<bool>[
        false,
        false,
        true,
        true,
      ], newestIsPendingToday: true);

      expect(tally.current, 0);
    });

    test('a completed today counts even with the pending flag set', () {
      final tally = StreakTally.fromMatchDays(<bool>[
        true,
        true,
      ], newestIsPendingToday: true);

      expect(tally.current, 2);
    });

    test('remembers the longest run in the window', () {
      final tally = StreakTally.fromMatchDays(<bool>[
        true,
        false,
        true,
        true,
        true,
        true,
      ]);

      expect(tally.current, 1);
      expect(tally.longest, 4);
    });

    test('an empty calendar is an empty tally', () {
      final tally = StreakTally.fromMatchDays(const <bool>[]);

      expect(tally.current, 0);
      expect(tally.longest, 0);
      expect(StreakTally.none.current, 0);
    });

    test('a run of days with no fixtures between them stays unbroken', () {
      // Days without fixtures never reach this list, so an international
      // break is invisible here -- which is exactly the intended behaviour.
      final tally = StreakTally.fromMatchDays(<bool>[true, true, true]);

      expect(tally.current, 3);
    });
  });
}
