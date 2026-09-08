import 'package:domain/src/competition/competition_id.dart';
import 'package:domain/src/competition/season_id.dart';

/// One finished-or-running season as it appears in a single user's record:
/// the season's display facts joined with where that user placed in it.
///
/// A cross-aggregate *projection*, exactly like [ParticipantSeasonFeedEntry],
/// and for the same reason: it carries what one read needs out of one joined
/// query and never crosses back into a write path. The difference is scope --
/// the feed entry answers "which seasons am I in right now", this answers
/// "how did I do, in every season I have played".
///
/// [rank] arrives from the standings view rather than being assigned here.
/// That is the one deliberate departure from [SeasonLeaderboard.rank], and it
/// is forced: ranking in the domain requires the whole season's standings in
/// memory, and this read deliberately fetches ONE row per season -- the
/// caller's. Loading every participant of every season the user ever played,
/// to rank them all and then discard all but one row, would cost the whole
/// platform's standings to answer a personal question. The view computes the
/// same standard-competition rank the domain does (`rank() over (partition by
/// season_id order by total_points desc)`), so the number agrees with the
/// board the user can open beside it.
final class ParticipantSeasonRecord {
  /// Creates a record row.
  const ParticipantSeasonRecord({
    required this.competitionId,
    required this.competitionName,
    required this.seasonId,
    required this.seasonLabel,
    required this.startAt,
    required this.endAt,
    required this.rank,
    required this.totalPoints,
    required this.entryCount,
    required this.exactCount,
    required this.settledCount,
  });

  /// The owning competition's identity.
  final CompetitionId competitionId;

  /// The owning competition's display name.
  final String competitionName;

  /// The season's identity -- the key for opening its full board.
  final SeasonId seasonId;

  /// The season's display label.
  final String seasonLabel;

  /// UTC instant the season's calendar window opens (inclusive).
  final DateTime startAt;

  /// UTC instant the season's calendar window closes (exclusive).
  final DateTime endAt;

  /// The place the user took, standard-competition ("1224") ranked.
  final int rank;

  /// The signed points total the user finished the season on.
  final int totalPoints;

  /// How many ledger entries make up [totalPoints].
  final int entryCount;

  /// Settled fixtures the user called EXACTLY right.
  final int exactCount;

  /// Fixtures settled for the user at all.
  final int settledCount;

  /// Whether the season's calendar window has closed by [nowUtc].
  bool isFinishedAt(DateTime nowUtc) => !endAt.isAfter(nowUtc);

  /// Accuracy as a whole percent, or null when nothing has settled yet.
  ///
  /// Null, not zero. A user whose first fixture has not been graded has no
  /// accuracy at all -- 0/0 -- and printing "0%" beside their name would read
  /// as a record of failure rather than an absence of evidence. The counts
  /// travel raw on the wire for exactly this reason (migration 0031); the
  /// division happens here, once.
  int? get accuracyPercent =>
      settledCount == 0 ? null : (exactCount * 100 / settledCount).round();

  @override
  bool operator ==(Object other) =>
      other is ParticipantSeasonRecord &&
      other.competitionId == competitionId &&
      other.competitionName == competitionName &&
      other.seasonId == seasonId &&
      other.seasonLabel == seasonLabel &&
      other.startAt == startAt &&
      other.endAt == endAt &&
      other.rank == rank &&
      other.totalPoints == totalPoints &&
      other.entryCount == entryCount &&
      other.exactCount == exactCount &&
      other.settledCount == settledCount;

  @override
  int get hashCode => Object.hash(
    competitionId,
    competitionName,
    seasonId,
    seasonLabel,
    startAt,
    endAt,
    rank,
    totalPoints,
    entryCount,
    exactCount,
    settledCount,
  );

  @override
  String toString() =>
      'ParticipantSeasonRecord(season: ${seasonId.value} "$seasonLabel", '
      'rank: $rank, points: $totalPoints, '
      'accuracy: $exactCount/$settledCount)';
}
