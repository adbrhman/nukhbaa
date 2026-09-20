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

  /// Finished a first week of the weekly league.
  leagueFirstWeek('league_first_week'),

  /// Was promoted at the end of a league week.
  leaguePromoted('league_promoted'),

  /// Finished first in a league group on more than zero points.
  leagueChampion('league_champion'),

  /// Finished a league week in the top tier.
  leagueElite('league_elite');

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
  };

  /// Every badge [progress] has earned, in catalog order.
  static List<BadgeCode> earnedBy(BadgeProgress progress) => <BadgeCode>[
    for (final code in BadgeCode.values)
      if (code.isEarnedBy(progress)) code,
  ];
}
