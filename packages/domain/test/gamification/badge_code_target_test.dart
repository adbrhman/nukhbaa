import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// Pins the badge wall's progress figures (P2-8) to the rules that grant the
/// badges (P2-6): a bar that reads full must be a badge the evaluator grants,
/// and a badge it grants must never show a bar short of full.
void main() {
  group('BadgeCode.countIn and target', () {
    test('agree with isEarnedBy on every count around each threshold', () {
      for (final code in BadgeCode.values) {
        for (var n = 0; n <= code.target + 2; n++) {
          final progress = BadgeProgress(
            predictionsPlaced: n,
            perfectDays: n,
            weeksFinished: n,
            promotions: n,
            weeksWon: n,
            eliteWeeks: n,
          );
          expect(
            code.isEarnedBy(progress),
            code.countIn(progress) >= code.target,
            reason: '${code.wireName} at $n',
          );
        }
      }
    });

    test('each badge reads only its own count', () {
      const progress = BadgeProgress(
        predictionsPlaced: 11,
        perfectDays: 12,
        weeksFinished: 13,
        promotions: 14,
        weeksWon: 15,
        eliteWeeks: 16,
      );

      expect(BadgeCode.predictions25.countIn(progress), 11);
      expect(BadgeCode.perfectDays7.countIn(progress), 12);
      expect(BadgeCode.leagueFirstWeek.countIn(progress), 13);
      expect(BadgeCode.leaguePromoted.countIn(progress), 14);
      expect(BadgeCode.leagueChampion.countIn(progress), 15);
      expect(BadgeCode.leagueElite.countIn(progress), 16);
    });

    test('every target is at least one', () {
      for (final code in BadgeCode.values) {
        expect(code.target, greaterThanOrEqualTo(1), reason: code.wireName);
      }
    });
  });
}
