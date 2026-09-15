import 'package:domain/src/identity/user_id.dart';
import 'package:shared/shared.dart';

/// The sporting season a contest month belongs to.
///
/// The contest is the calendar month; the sporting season is twelve of them,
/// September through the following August, and whoever holds the most points
/// summed over those months is the season champion. A season is identified by
/// the year its September falls in.
final class SportingSeason {
  const SportingSeason._(this.startYear);

  /// The season that contains [instant] (read in UTC).
  factory SportingSeason.containing(DateTime instant) {
    final utc = instant.toUtc();
    return SportingSeason._(utc.month >= firstMonth ? utc.year : utc.year - 1);
  }

  /// The calendar month every season opens with.
  static const int firstMonth = 9;

  /// The year the season's September falls in.
  final int startYear;

  /// The year the season's August falls in.
  int get endYear => startYear + 1;

  /// `yyyymm` of the season's first month (September), inclusive.
  int get firstMonthKey => startYear * 100 + firstMonth;

  /// `yyyymm` of the season's last month (August), inclusive.
  int get lastMonthKey => endYear * 100 + firstMonth - 1;

  /// Display label, e.g. `2026/2027`.
  String get label => '$startYear/$endYear';

  @override
  bool operator ==(Object other) =>
      other is SportingSeason && other.startYear == startYear;

  @override
  int get hashCode => startYear.hashCode;

  @override
  String toString() => 'SportingSeason($label)';
}

/// One user's line on the sporting-season board: the sums of their monthly
/// fixture standings across every month of the season. Every number is a
/// sum of points the scoring context already stored; nothing is recomputed.
final class SportingSeasonStanding {
  const SportingSeasonStanding._({
    required this.userId,
    required this.displayName,
    required this.totalPoints,
    required this.fixturesScored,
    required this.exactCount,
    required this.decidedCount,
    required this.monthsPlayed,
    required this.rank,
  });

  /// Builds an unranked projection, refusing impossible counts.
  static Result<SportingSeasonStanding> projected({
    required UserId userId,
    required String displayName,
    required int totalPoints,
    required int fixturesScored,
    required int exactCount,
    required int decidedCount,
    required int monthsPlayed,
  }) {
    if (fixturesScored < 0 ||
        exactCount < 0 ||
        decidedCount < 0 ||
        monthsPlayed < 0) {
      return const Result.err(
        AppError.invariant(
          'sporting_season.count_negative',
          'A season standing cannot carry a negative count',
        ),
      );
    }
    if (exactCount > decidedCount) {
      return const Result.err(
        AppError.invariant(
          'sporting_season.exact_exceeds_decided',
          'Exact calls cannot outnumber decided fixtures',
        ),
      );
    }
    return Result.ok(
      SportingSeasonStanding._(
        userId: userId,
        displayName: displayName,
        totalPoints: totalPoints,
        fixturesScored: fixturesScored,
        exactCount: exactCount,
        decidedCount: decidedCount,
        monthsPlayed: monthsPlayed,
        rank: _unassignedRank,
      ),
    );
  }

  static const int _unassignedRank = 0;

  /// The user the line belongs to -- constant across the season's months.
  final UserId userId;

  /// The platform-owned display name.
  final String displayName;

  /// Points summed over every month of the season.
  final int totalPoints;

  /// Scored fixtures summed over the season.
  final int fixturesScored;

  /// Decided fixtures called exactly right.
  final int exactCount;

  /// Decided fixtures in total (missed and pending excluded).
  final int decidedCount;

  /// How many of the season's months contributed.
  final int monthsPlayed;

  /// Standard-competition ("1224") rank; 0 until ranked.
  final int rank;

  /// Returns this line placed at [assignedRank].
  Result<SportingSeasonStanding> withRank(int assignedRank) {
    if (assignedRank < 1) {
      return const Result.err(
        AppError.invariant(
          'sporting_season.rank_not_positive',
          'A season rank must be a positive 1-based position',
        ),
      );
    }
    return Result.ok(
      SportingSeasonStanding._(
        userId: userId,
        displayName: displayName,
        totalPoints: totalPoints,
        fixturesScored: fixturesScored,
        exactCount: exactCount,
        decidedCount: decidedCount,
        monthsPlayed: monthsPlayed,
        rank: assignedRank,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SportingSeasonStanding &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.totalPoints == totalPoints &&
      other.fixturesScored == fixturesScored &&
      other.exactCount == exactCount &&
      other.decidedCount == decidedCount &&
      other.monthsPlayed == monthsPlayed &&
      other.rank == rank;

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    totalPoints,
    fixturesScored,
    exactCount,
    decidedCount,
    monthsPlayed,
    rank,
  );
}

/// The ranked sporting-season board: most points first, ties sharing a rank
/// (standard competition ranking), ties broken for display by user id so the
/// order is total and stable.
final class SportingSeasonLeaderboard {
  const SportingSeasonLeaderboard._({
    required this.season,
    required this.entries,
  });

  /// Ranks [standings] for [season]. A user appearing twice is an invariant
  /// breach in the projection, never silently merged.
  static Result<SportingSeasonLeaderboard> rank({
    required SportingSeason season,
    required List<SportingSeasonStanding> standings,
  }) {
    final seen = <String>{};
    for (final standing in standings) {
      if (!seen.add(standing.userId.value)) {
        return Result.err(
          AppError.invariant(
            'sporting_season.duplicate_user',
            'User ${standing.userId.value} appears more than once on the '
                'season board',
          ),
        );
      }
    }

    final ordered = List<SportingSeasonStanding>.of(standings)..sort(_compare);
    final ranked = <SportingSeasonStanding>[];
    for (var i = 0; i < ordered.length; i++) {
      final standing = ordered[i];
      final assigned =
          i > 0 && ordered[i - 1].totalPoints == standing.totalPoints
          ? ranked[i - 1].rank
          : i + 1;
      final placed = standing.withRank(assigned);
      if (placed is Err<SportingSeasonStanding>) {
        return Result.err(placed.error);
      }
      ranked.add((placed as Ok<SportingSeasonStanding>).value);
    }

    return Result.ok(
      SportingSeasonLeaderboard._(
        season: season,
        entries: List<SportingSeasonStanding>.unmodifiable(ranked),
      ),
    );
  }

  static int _compare(SportingSeasonStanding a, SportingSeasonStanding b) {
    final byPoints = b.totalPoints.compareTo(a.totalPoints);
    if (byPoints != 0) {
      return byPoints;
    }
    return a.userId.value.compareTo(b.userId.value);
  }

  /// The season this board ranks.
  final SportingSeason season;

  /// The ranked lines, best first.
  final List<SportingSeasonStanding> entries;
}
