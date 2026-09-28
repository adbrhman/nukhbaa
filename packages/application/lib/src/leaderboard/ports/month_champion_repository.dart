import 'package:application/src/identity/ports/user_directory.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Read/write port for the crowned champions of the monthly contests
/// (migration 0077).
///
/// The adapter stores and reads; every rule (who may be crowned, when) is the
/// use-cases'. The database triggers are only the backstop.
///
/// General contract: MUST NOT throw; infrastructure failures are
/// [ErrorKind.transient].
abstract interface class MonthChampionRepository {
  /// The month [season] as the crowning needs it, or `Ok(null)` when there is
  /// no such season.
  Future<Result<ChampionMonth?>> month(SeasonId season);

  /// Crowns [champions] in [season], all at [crownedAt] by [crownedBy], in
  /// one transaction.
  Future<Result<void>> crown({
    required SeasonId season,
    required List<ChampionToCrown> champions,
    required UserId crownedBy,
    required DateTime crownedAt,
  });

  /// The crowned champions, newest crowning first, at most [limit] rows.
  Future<Result<List<MonthChampion>>> list({required int limit});

  /// Sets or replaces the celebration picture of [user], crowned in
  /// [season]. `Ok(false)` when [user] is not a champion of [season].
  Future<Result<bool>> setPhoto({
    required SeasonId season,
    required UserId user,
    required List<int> bytes,
    required String mime,
    required DateTime now,
  });

  /// The celebration picture of [user] in [season], or `Ok(null)` when there
  /// is none.
  Future<Result<StoredAvatar?>> photo({
    required SeasonId season,
    required UserId user,
  });
}

/// A monthly contest as the crowning reads it.
final class ChampionMonth {
  /// Creates the month.
  const ChampionMonth({
    required this.seasonId,
    required this.label,
    required this.startAt,
    required this.endAt,
    required this.fixtures,
    required this.unscoredFixtures,
    required this.crowned,
  });

  /// The contest.
  final SeasonId seasonId;

  /// Its label (`09/2026`).
  final String label;

  /// When it opened (UTC).
  final DateTime startAt;

  /// When it closed (UTC, exclusive).
  final DateTime endAt;

  /// Every fixture linked to it, in display order -- the fixtures its board
  /// sums.
  final List<FixtureRef> fixtures;

  /// How many of [fixtures] have no recorded result yet.
  final int unscoredFixtures;

  /// The players already crowned in it (empty until it is crowned).
  final List<UserId> crowned;
}

/// One champion to crown, with the final figures frozen as they stood.
final class ChampionToCrown {
  /// Creates the row.
  const ChampionToCrown({
    required this.userId,
    required this.points,
    required this.exactCount,
    required this.decidedCount,
    required this.referralPoints,
  });

  /// The champion.
  final UserId userId;

  /// Prediction points on the final board.
  final int points;

  /// Exact scorelines.
  final int exactCount;

  /// Decided fixtures (the accuracy's denominator).
  final int decidedCount;

  /// The month's invitation points (a tie-break only).
  final int referralPoints;
}

/// A crowned champion as it is read back.
final class MonthChampion {
  /// Creates the record.
  const MonthChampion({
    required this.seasonId,
    required this.seasonLabel,
    required this.userId,
    required this.displayName,
    required this.points,
    required this.exactCount,
    required this.decidedCount,
    required this.referralPoints,
    required this.crownedAt,
    this.photoUpdatedAt,
    this.avatarUpdatedAt,
  });

  /// The month.
  final SeasonId seasonId;

  /// Its label (`09/2026`).
  final String seasonLabel;

  /// The champion.
  final UserId userId;

  /// The champion's current display name.
  final String displayName;

  /// Prediction points on the final board.
  final int points;

  /// Exact scorelines.
  final int exactCount;

  /// Decided fixtures.
  final int decidedCount;

  /// The month's invitation points.
  final int referralPoints;

  /// When the month was crowned (UTC).
  final DateTime crownedAt;

  /// When the celebration picture was set (UTC), or null without one.
  final DateTime? photoUpdatedAt;

  /// When the champion's own profile picture was set (UTC), or null without
  /// one -- the fallback when there is no celebration picture.
  final DateTime? avatarUpdatedAt;
}
