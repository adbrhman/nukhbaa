import 'package:shared/shared.dart';

/// One Riyadh day as the daily selection left it (script 190).
final class DailySelectionDay {
  /// Creates the entry.
  const DailySelectionDay({
    required this.day,
    required this.mode,
    required this.baseCount,
    required this.target,
    required this.busy,
    required this.chosen,
    required this.finalCount,
    required this.note,
  });

  /// The Riyadh day, as a UTC midnight.
  final DateTime day;

  /// `shadow` or `on`.
  final String mode;

  /// The day's matches before the selection: the Premier League, the
  /// Champions League, the admins' own and (when on) those chosen earlier.
  final int baseCount;

  /// 15, or 20 on a busy day.
  final int target;

  /// Whether the four big leagues all play that day.
  final bool busy;

  /// Matches chosen by this run.
  final int chosen;

  /// The day's matches after it (would be, in shadow mode).
  final int finalCount;

  /// Anything else worth reading: an alert sent or due, a league not read.
  final String note;
}

/// One match the selection looked at, with its score and what it decided.
final class DailySelectionCandidate {
  /// Creates the entry.
  const DailySelectionCandidate({
    required this.source,
    required this.externalId,
    required this.leagueName,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    required this.score,
    required this.reasons,
    required this.decision,
  });

  /// The provider (`football-data`, `highlightly`).
  final String source;

  /// The provider's match id.
  final String externalId;

  /// The catalog league name.
  final String leagueName;

  /// The home club, by its catalog name when mapped.
  final String homeTeam;

  /// The away club, the same way.
  final String awayTeam;

  /// Kickoff, UTC.
  final DateTime kickoffAt;

  /// Its score, or null when it could not be chosen at all.
  final int? score;

  /// How the score was made, in Arabic.
  final String reasons;

  /// What the selection did with it, in Arabic.
  final String decision;
}

/// Where the daily selection keeps what it decided and why
/// (`football_data.daily_selection_days` and `..._candidates`, migration
/// 0193), so the trial week can be read back and the weights tuned.
abstract interface class DailySelectionLog {
  /// Keeps [day] and its [candidates] in place of what an earlier run of the
  /// same day kept.
  Future<Result<void>> record({
    required DailySelectionDay day,
    required List<DailySelectionCandidate> candidates,
    required DateTime at,
  });
}

/// Tells the owner admin, in the app, that a coming day is short of
/// matches (script 190). Only his account: never every admin.
abstract interface class DailyShortfallAlert {
  /// Sends one in-app notification about [day], which holds
  /// [fixtureCount] matches of the [minimum]; its first match kicks off at
  /// [firstKickoff] (null when it has none).
  Future<Result<void>> send({
    required DateTime day,
    required int fixtureCount,
    required int minimum,
    required DateTime? firstKickoff,
  });
}
