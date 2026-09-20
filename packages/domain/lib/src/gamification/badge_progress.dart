/// What a player's history in the gamification stream adds up to, as far as
/// the badge catalog is concerned (P2-6).
///
/// A plain tally, counted from `gamification.events` by the badge reader. It
/// holds no clock, no id and no points: the rules of the catalog
/// (`BadgeCode.isEarnedBy`) are pure comparisons over these counts, which is
/// what keeps them testable without a database.
///
/// Every count is a number of events, and every event is keyed so that it is
/// written once, so a count never overstates the history it summarises.
final class BadgeProgress {
  /// Creates a tally; every count defaults to zero (a player with no history).
  const BadgeProgress({
    this.predictionsPlaced = 0,
    this.perfectDays = 0,
    this.weeksFinished = 0,
    this.promotions = 0,
    this.weeksWon = 0,
    this.eliteWeeks = 0,
  });

  /// First-time prediction submissions (`prediction_placed`).
  final int predictionsPlaced;

  /// Riyadh match days on which every fixture was predicted
  /// (`daily_challenge_completed`).
  final int perfectDays;

  /// Weekly-league weeks judged for the player (`weekly_league_finished`).
  final int weeksFinished;

  /// Judged weeks that ended in a promotion.
  final int promotions;

  /// Judged weeks the player finished first in the group with more than zero
  /// points. A first place on zero points is a group nobody played in.
  final int weeksWon;

  /// Judged weeks played in the top tier of the ladder.
  final int eliteWeeks;
}
