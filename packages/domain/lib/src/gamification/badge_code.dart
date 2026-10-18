import 'package:domain/src/gamification/badge_progress.dart';

/// The badge catalog (P2-6): each badge is a code and the rule that earns it.
///
/// This enum, not a table, is the authoritative catalog. A badge is held when
/// the player's stream contains a `badge_unlocked` event for it, and that
/// event is keyed on the user and [wireName], so a badge is granted once and,
/// the stream being append-only, never taken back. A badge carries no points:
/// the reward is the record.
///
/// The [wireName] values are a storage contract. They sit inside dedupe keys
/// already written, so a code is never renamed or reused; a badge that is
/// retired is left here (or its stored events are ignored by the reader) and
/// a new one takes a new code. Display names live in l10n, not here.
///
/// A rule is a pure comparison over a [BadgeProgress]. Thresholds are
/// inclusive and each rule reads only its own count.
///
/// A retired badge ([isRetired]) keeps its code here, because its events are
/// stored, but it is never awarded again and never shown ([active]). The four
/// weekly-league badges were retired on 2026-10-18, when the monthly
/// head-to-head league replaced the weekly league on screen; the four
/// head-to-head badges took their place (decided by the owner).
enum BadgeCode {
  /// Placed a first prediction.
  firstPrediction('first_prediction'),

  /// Placed 25 predictions.
  predictions25('predictions_25'),

  /// Placed 100 predictions.
  predictions100('predictions_100'),

  /// Completed a first match day: predicted every fixture of one day.
  firstPerfectDay('first_perfect_day'),

  /// Completed 7 match days.
  perfectDays7('perfect_days_7'),

  /// Completed 30 match days.
  perfectDays30('perfect_days_30'),

  /// Finished a first week of the weekly league. Retired.
  leagueFirstWeek('league_first_week'),

  /// Was promoted at the end of a league week. Retired.
  leaguePromoted('league_promoted'),

  /// Finished first in a league group on more than zero points. Retired.
  leagueChampion('league_champion'),

  /// Finished a league week in the top tier. Retired.
  leagueElite('league_elite'),

  /// Finished a first month of the head-to-head league.
  h2hFirstMonth('h2h_first_month'),

  /// Was promoted at the end of a head-to-head month.
  h2hPromoted('h2h_promoted'),

  /// Finished first in a head-to-head group with more than zero league
  /// points.
  h2hChampion('h2h_champion'),

  /// Finished a head-to-head month in the first division.
  h2hFirstDivision('h2h_first_division');

  const BadgeCode(this.wireName);

  /// The code stored in the `badge_unlocked` event and in its dedupe key.
  final String wireName;

  /// The badge stored as [raw], or null if it names none (a retired code, a
  /// blank, a different casing).
  static BadgeCode? tryParse(String? raw) {
    for (final code in BadgeCode.values) {
      if (code.wireName == raw) {
        return code;
      }
    }
    return null;
  }

  /// Whether [progress] has earned this badge.
  bool isEarnedBy(BadgeProgress progress) => switch (this) {
    BadgeCode.firstPrediction => progress.predictionsPlaced >= 1,
    BadgeCode.predictions25 => progress.predictionsPlaced >= 25,
    BadgeCode.predictions100 => progress.predictionsPlaced >= 100,
    BadgeCode.firstPerfectDay => progress.perfectDays >= 1,
    BadgeCode.perfectDays7 => progress.perfectDays >= 7,
    BadgeCode.perfectDays30 => progress.perfectDays >= 30,
    BadgeCode.leagueFirstWeek => progress.weeksFinished >= 1,
    BadgeCode.leaguePromoted => progress.promotions >= 1,
    BadgeCode.leagueChampion => progress.weeksWon >= 1,
    BadgeCode.leagueElite => progress.eliteWeeks >= 1,
    BadgeCode.h2hFirstMonth => progress.monthsFinished >= 1,
    BadgeCode.h2hPromoted => progress.monthPromotions >= 1,
    BadgeCode.h2hChampion => progress.monthsWon >= 1,
    BadgeCode.h2hFirstDivision => progress.firstDivisionMonths >= 1,
  };

  /// The count this badge's rule reads from [progress].
  int countIn(BadgeProgress progress) => switch (this) {
    BadgeCode.firstPrediction ||
    BadgeCode.predictions25 ||
    BadgeCode.predictions100 => progress.predictionsPlaced,
    BadgeCode.firstPerfectDay ||
    BadgeCode.perfectDays7 ||
    BadgeCode.perfectDays30 => progress.perfectDays,
    BadgeCode.leagueFirstWeek => progress.weeksFinished,
    BadgeCode.leaguePromoted => progress.promotions,
    BadgeCode.leagueChampion => progress.weeksWon,
    BadgeCode.leagueElite => progress.eliteWeeks,
    BadgeCode.h2hFirstMonth => progress.monthsFinished,
    BadgeCode.h2hPromoted => progress.monthPromotions,
    BadgeCode.h2hChampion => progress.monthsWon,
    BadgeCode.h2hFirstDivision => progress.firstDivisionMonths,
  };

  /// The count at which the badge is earned (inclusive): [isEarnedBy] holds
  /// exactly when `countIn(progress) >= target`. Shown to the player as the
  /// far end of a progress bar.
  int get target => switch (this) {
    BadgeCode.firstPrediction => 1,
    BadgeCode.predictions25 => 25,
    BadgeCode.predictions100 => 100,
    BadgeCode.firstPerfectDay => 1,
    BadgeCode.perfectDays7 => 7,
    BadgeCode.perfectDays30 => 30,
    BadgeCode.leagueFirstWeek => 1,
    BadgeCode.leaguePromoted => 1,
    BadgeCode.leagueChampion => 1,
    BadgeCode.leagueElite => 1,
    BadgeCode.h2hFirstMonth => 1,
    BadgeCode.h2hPromoted => 1,
    BadgeCode.h2hChampion => 1,
    BadgeCode.h2hFirstDivision => 1,
  };

  /// Whether this badge is retired: never awarded again and never shown,
  /// though a `badge_unlocked` event already written for it stays stored.
  bool get isRetired => switch (this) {
    BadgeCode.leagueFirstWeek ||
    BadgeCode.leaguePromoted ||
    BadgeCode.leagueChampion ||
    BadgeCode.leagueElite => true,
    BadgeCode.firstPrediction ||
    BadgeCode.predictions25 ||
    BadgeCode.predictions100 ||
    BadgeCode.firstPerfectDay ||
    BadgeCode.perfectDays7 ||
    BadgeCode.perfectDays30 ||
    BadgeCode.h2hFirstMonth ||
    BadgeCode.h2hPromoted ||
    BadgeCode.h2hChampion ||
    BadgeCode.h2hFirstDivision => false,
  };

  /// The badges still awarded and shown, in catalog order.
  static List<BadgeCode> get active => <BadgeCode>[
    for (final code in BadgeCode.values)
      if (!code.isRetired) code,
  ];

  /// Every active badge [progress] has earned, in catalog order. A retired
  /// badge is never earned again, whatever the counts say.
  static List<BadgeCode> earnedBy(BadgeProgress progress) => <BadgeCode>[
    for (final code in active)
      if (code.isEarnedBy(progress)) code,
  ];
}
