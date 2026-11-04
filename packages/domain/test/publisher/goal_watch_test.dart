import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('GoalWatch.diff', () {
    test('an unchanged score changes nothing', () {
      final change = GoalWatch.diff(
        const ScoreLine(1, 0),
        const ScoreLine(1, 0),
      );

      expect(change.isEmpty, isTrue);
    });

    test('one home goal from 0-0 is the first home goal', () {
      final change = GoalWatch.diff(ScoreLine.nil, const ScoreLine(1, 0));

      expect(change.added, <GoalStep>[
        const GoalStep(home: true, before: ScoreLine.nil),
      ]);
      expect(change.added.single.key, 'h1');
      expect(change.added.single.after, const ScoreLine(1, 0));
      expect(change.withdrawn, isEmpty);
      expect(change.bothSidesScored, isFalse);
    });

    test('two away goals between reads are two steps in order', () {
      final change = GoalWatch.diff(
        const ScoreLine(1, 0),
        const ScoreLine(1, 2),
      );

      expect(
        <String>[for (final step in change.added) step.key],
        <String>['a1', 'a2'],
      );
      expect(change.added.last.before, const ScoreLine(1, 1));
      expect(change.bothSidesScored, isFalse);
    });

    test('both sides scoring between reads is flagged, home goals first', () {
      final change = GoalWatch.diff(ScoreLine.nil, const ScoreLine(1, 1));

      expect(
        <String>[for (final step in change.added) step.key],
        <String>['h1', 'a1'],
      );
      expect(change.bothSidesScored, isTrue);
    });

    test('a goal the feed takes back is withdrawn by its key', () {
      final change = GoalWatch.diff(
        const ScoreLine(2, 1),
        const ScoreLine(1, 1),
      );

      expect(change.withdrawn, <String>['h2']);
      expect(change.added, isEmpty);
    });

    test('a goal taken back and another given in one read keeps both', () {
      // 1-0 read as 0-1: the home goal was ruled out, the away side scored.
      final change = GoalWatch.diff(
        const ScoreLine(1, 0),
        const ScoreLine(0, 1),
      );

      expect(change.withdrawn, <String>['h1']);
      expect(change.added, <GoalStep>[
        const GoalStep(home: false, before: ScoreLine.nil),
      ]);
    });
  });

  group('GoalWatch.confirmed', () {
    const step = GoalStep(home: true, before: ScoreLine(0, 1));
    final seenAt = DateTime.utc(2026, 11, 7, 18, 10);

    test('stands once the hold has passed with the goal still counted', () {
      expect(
        GoalWatch.confirmed(
          step: step,
          seen: const ScoreLine(1, 1),
          firstSeenAt: seenAt,
          now: seenAt.add(const Duration(minutes: 3)),
          hold: const Duration(minutes: 3),
        ),
        isTrue,
      );
    });

    test('waits while the hold has not passed', () {
      expect(
        GoalWatch.confirmed(
          step: step,
          seen: const ScoreLine(1, 1),
          firstSeenAt: seenAt,
          now: seenAt.add(const Duration(minutes: 2, seconds: 59)),
          hold: const Duration(minutes: 3),
        ),
        isFalse,
      );
    });

    test('never stands once the feed no longer counts it', () {
      expect(
        GoalWatch.confirmed(
          step: step,
          seen: const ScoreLine(0, 1),
          firstSeenAt: seenAt,
          now: seenAt.add(const Duration(minutes: 10)),
          hold: const Duration(minutes: 3),
        ),
        isFalse,
      );
    });

    test('a later goal of the same side keeps an earlier one counted', () {
      expect(GoalWatch.stillCounted(step, const ScoreLine(2, 1)), isTrue);
    });
  });
}
