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
        'h2h_first_month',
        'h2h_promoted',
        'h2h_champion',
        'h2h_first_division',
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

    test('the weekly-league badges are retired and never earned again', () {
      expect(
        BadgeCode.earnedBy(
          const BadgeProgress(
            weeksFinished: 1000,
            promotions: 1000,
            weeksWon: 1000,
            eliteWeeks: 1000,
          ),
        ),
        isEmpty,
      );
      expect(
        <BadgeCode>[
          for (final code in BadgeCode.values)
            if (code.isRetired) code,
        ],
        <BadgeCode>[
          BadgeCode.leagueFirstWeek,
          BadgeCode.leaguePromoted,
          BadgeCode.leagueChampion,
          BadgeCode.leagueElite,
        ],
      );
      expect(BadgeCode.active, <BadgeCode>[
        BadgeCode.firstPrediction,
        BadgeCode.predictions25,
        BadgeCode.predictions100,
        BadgeCode.firstPerfectDay,
        BadgeCode.perfectDays7,
        BadgeCode.perfectDays30,
        BadgeCode.h2hFirstMonth,
        BadgeCode.h2hPromoted,
        BadgeCode.h2hChampion,
        BadgeCode.h2hFirstDivision,
      ]);
    });

    test('each head-to-head badge reads only its own count', () {
      expect(
        BadgeCode.earnedBy(const BadgeProgress(monthsFinished: 1)),
        <BadgeCode>[BadgeCode.h2hFirstMonth],
      );
      expect(
        BadgeCode.earnedBy(const BadgeProgress(monthPromotions: 1)),
        <BadgeCode>[BadgeCode.h2hPromoted],
      );
      expect(BadgeCode.earnedBy(const BadgeProgress(monthsWon: 1)), <BadgeCode>[
        BadgeCode.h2hChampion,
      ]);
      expect(
        BadgeCode.earnedBy(const BadgeProgress(firstDivisionMonths: 1)),
        <BadgeCode>[BadgeCode.h2hFirstDivision],
      );
    });

    test('a full history earns the active catalog, in catalog order', () {
      const full = BadgeProgress(
        predictionsPlaced: 1000,
        perfectDays: 1000,
        weeksFinished: 1000,
        promotions: 1000,
        weeksWon: 1000,
        eliteWeeks: 1000,
        monthsFinished: 1000,
        monthPromotions: 1000,
        monthsWon: 1000,
        firstDivisionMonths: 1000,
      );

      expect(BadgeCode.earnedBy(full), BadgeCode.active);
    });
  });
}
