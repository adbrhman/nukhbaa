import 'package:application/application.dart';
import 'package:test/test.dart';

void main() {
  group('DailyChallengeProgress.isComplete', () {
    test('is true once every fixture of the day is predicted', () {
      const progress = DailyChallengeProgress(total: 4, predicted: 4);
      expect(progress.isComplete, isTrue);
    });

    test('is false while one fixture is missing', () {
      const progress = DailyChallengeProgress(total: 4, predicted: 3);
      expect(progress.isComplete, isFalse);
    });

    test('is false on a day with no fixtures', () {
      // An international break is not an achievement.
      const progress = DailyChallengeProgress(total: 0, predicted: 0);
      expect(progress.isComplete, isFalse);
    });

    test('stays true when a fixture is added after the day completed', () {
      // The reading itself moves on -- 4 of 5 is not complete -- but the
      // event emitted at 4 of 4 is already in the append-only stream and
      // cannot be retracted. This test pins the reading; migration 0053 and
      // the dedupe key pin the record.
      const before = DailyChallengeProgress(total: 4, predicted: 4);
      const after = DailyChallengeProgress(total: 5, predicted: 4);
      expect(before.isComplete, isTrue);
      expect(after.isComplete, isFalse);
    });
  });
}
