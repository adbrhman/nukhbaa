import 'package:domain/domain.dart';
import 'package:test/test.dart';

/// Hermetic tests for the badge catalog (P2-6): the codes are a storage
/// contract, and every rule is a pure comparison over a [BadgeProgress].
void main() {
  group('BadgeCode', () {
    test('the wire names are the stored contract, in catalog order', () {
      final names = <String>[
        for (final code in BadgeCode.values) code.wireName,
      ];

      expect(names, <String>[
        'first_prediction',
        'predictions_25',
        'predictions_100',
        'first_perfect_day',
        'perfect_days_7',
        'perfect_days_30',
        'league_first_week',
        'league_promoted',
        'league_champion',
        'league_elite',
      ]);
    });

    test('tryParse reads every wire name and nothing else', () {
      for (final code in BadgeCode.values) {
        expect(BadgeCode.tryParse(code.wireName), code);
      }
      expect(BadgeCode.tryParse(null), isNull);
      expect(BadgeCode.tryParse(''), isNull);
      expect(BadgeCode.tryParse('FIRST_PREDICTION'), isNull);
      expect(BadgeCode.tryParse('retired_badge'), isNull);
    });

    test('a player with no history earns nothing', () {
      expect(BadgeCode.earnedBy(const BadgeProgress()), isEmpty);
    });

    test('the prediction badges open at 1, 25 and 100 inclusive', () {
      expect(
        BadgeCode.earnedBy(const BadgeProgress(predictionsPlaced: 1)),
        <BadgeCode>[BadgeCode.firstPrediction],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(predictionsPlaced: 24)),
        <BadgeCode>[BadgeCode.firstPrediction],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(predictionsPlaced: 25)),
        <BadgeCode>[BadgeCode.firstPrediction, BadgeCode.predictions25],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(predictionsPlaced: 99)),
        <BadgeCode>[BadgeCode.firstPrediction, BadgeCode.predictions25],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(predictionsPlaced: 100)),
        <BadgeCode>[
          BadgeCode.firstPrediction,
          BadgeCode.predictions25,
          BadgeCode.predictions100,
        ],
      );
    });

    test('the perfect-day badges open at 1, 7 and 30 inclusive', () {
      expect(
        BadgeCode.earnedBy(const BadgeProgress(perfectDays: 1)),
        <BadgeCode>[BadgeCode.firstPerfectDay],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(perfectDays: 6)),
        <BadgeCode>[BadgeCode.firstPerfectDay],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(perfectDays: 7)),
        <BadgeCode>[BadgeCode.firstPerfectDay, BadgeCode.perfectDays7],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(perfectDays: 29)),
        <BadgeCode>[BadgeCode.firstPerfectDay, BadgeCode.perfectDays7],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(perfectDays: 30)),
        <BadgeCode>[
          BadgeCode.firstPerfectDay,
          BadgeCode.perfectDays7,
          BadgeCode.perfectDays30,
        ],
      );
    });

    test('each league badge reads only its own count', () {
      expect(
        BadgeCode.earnedBy(const BadgeProgress(weeksFinished: 1)),
        <BadgeCode>[BadgeCode.leagueFirstWeek],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(promotions: 1)),
        <BadgeCode>[BadgeCode.leaguePromoted],
      );
      expect(BadgeCode.earnedBy(const BadgeProgress(weeksWon: 1)), <BadgeCode>[
        BadgeCode.leagueChampion,
      ]);
      expect(
        BadgeCode.earnedBy(const BadgeProgress(eliteWeeks: 1)),
        <BadgeCode>[BadgeCode.leagueElite],
      );
    });

    test('a full history earns the whole catalog, in catalog order', () {
      const full = BadgeProgress(
        predictionsPlaced: 1000,
        perfectDays: 1000,
        weeksFinished: 1000,
        promotions: 1000,
        weeksWon: 1000,
        eliteWeeks: 1000,
      );

      expect(BadgeCode.earnedBy(full), BadgeCode.values);
    });
  });
}
