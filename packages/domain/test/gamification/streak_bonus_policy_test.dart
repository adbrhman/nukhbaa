import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('StreakBonusPolicy.rungs', () {
    test('are the decided ladder: 7 -> 5, 14 -> 10, 30 -> 20', () {
      final ladder = <(int, int)>[
        for (final rung in StreakBonusPolicy.rungs)
          (rung.threshold, rung.points),
      ];

      expect(ladder, <(int, int)>[(7, 5), (14, 10), (30, 20)]);
    });

    test('ascend strictly and never pay a negative amount', () {
      final rungs = StreakBonusPolicy.rungs;
      for (var i = 1; i < rungs.length; i++) {
        expect(rungs[i].threshold, greaterThan(rungs[i - 1].threshold));
      }
      for (final rung in rungs) {
        expect(rung.points, greaterThan(0));
      }
    });

    test('name their ledger source_ref after the threshold', () {
      expect(
        <String>[for (final rung in StreakBonusPolicy.rungs) rung.sourceRef],
        <String>['streak:7', 'streak:14', 'streak:30'],
      );
    });
  });

  group('StreakBonusPolicy.reachedBy', () {
    List<int> thresholds(int current) => <int>[
      for (final rung in StreakBonusPolicy.reachedBy(current)) rung.threshold,
    ];

    test('is empty below the first rung', () {
      expect(thresholds(0), isEmpty);
      expect(thresholds(6), isEmpty);
      expect(thresholds(-1), isEmpty);
    });

    test('reaches a rung exactly at its threshold', () {
      expect(thresholds(7), <int>[7]);
      expect(thresholds(14), <int>[7, 14]);
      expect(thresholds(30), <int>[7, 14, 30]);
    });

    test('holds a rung between thresholds', () {
      expect(thresholds(13), <int>[7]);
      expect(thresholds(29), <int>[7, 14]);
    });

    test('a run past the last rung earns no more than the ladder holds', () {
      expect(thresholds(31), <int>[7, 14, 30]);
      expect(thresholds(400), <int>[7, 14, 30]);
    });

    test('reaches every lower rung too, so a missed payment is caught up', () {
      // A run that is already at 14 when it is first evaluated owes both
      // the 7 and the 14 rung.
      expect(thresholds(14), containsAll(<int>[7, 14]));
    });
  });
}
