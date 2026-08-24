import 'package:domain/src/competition/participant_id.dart';
import 'package:shared/shared.dart';

/// One participant's line on a **season-scoped, live "monthly" fixture
/// leaderboard** — the per-fixture sibling of `RoundLeaderboardEntry` under
/// Axiom 4 Amendment ("ScoreFixture replaces ScoreRound"; there is no round
/// left to rank within, so this ranks the season's individually-scored
/// fixtures instead).
///
/// Unlike `RoundLeaderboardEntry` (one already-summed `RoundScore` per
/// participant), this aggregates **multiple** already-computed
/// `ParticipantFixtureScore` rows — one per fixture the participant has been
/// scored on so far — into a single running [totalPoints] (Axiom 5: still
/// the SAME points already produced per fixture; this only sums and orders,
/// never recomputes a point value). [fixturesScored] is the count of
/// fixtures contributing to that total — a transparency/audit field, and the
/// natural way to show a **partial/live** standing: a participant with fewer
/// fixtures scored so far still has a total, since scoring is live and
/// per-fixture, never waiting for the rest of the season's fixtures to be
/// scored.
///
/// [rank] is the standard-competition ("1224") rank assigned by
/// `FixtureLeaderboard.rank` over the fully ordered board — never computed
/// by this value in isolation.
final class FixtureLeaderboardEntry {
  const FixtureLeaderboardEntry._({
    required this.participantId,
    required this.totalPoints,
    required this.fixturesScored,
    required this.rank,
  });

  /// Builds an **unranked** entry from a participant's already-summed
  /// [totalPoints] and how many fixtures ([fixturesScored]) contributed to
  /// it. The [rank] is left `0` (unassigned) — a meaningful rank exists only
  /// relative to the whole ordered board, so it is assigned later by
  /// `FixtureLeaderboard.rank`.
  factory FixtureLeaderboardEntry.aggregate({
    required ParticipantId participantId,
    required int totalPoints,
    required int fixturesScored,
  }) {
    return FixtureLeaderboardEntry._(
      participantId: participantId,
      totalPoints: totalPoints,
      fixturesScored: fixturesScored,
      rank: _unassignedRank,
    );
  }

  /// The sentinel rank of an entry that has not yet been placed on a board.
  static const int _unassignedRank = 0;

  /// The participant this line belongs to (by id).
  final ParticipantId participantId;

  /// The running total of every fixture score this participant has been
  /// awarded so far this season (never recomputed here).
  final int totalPoints;

  /// How many of the season's fixtures have been scored for this participant
  /// so far — an audit/transparency count for the live/partial board (a
  /// season with unscored fixtures remaining is a normal, ongoing state,
  /// never an error).
  final int fixturesScored;

  /// The participant's standard-competition ("1224") rank on the board, or
  /// `0` while unassigned. Assigned by `FixtureLeaderboard`.
  final int rank;

  /// Whether this entry has been placed on a board (has a meaningful [rank]).
  bool get isRanked => rank != _unassignedRank;

  /// Returns a copy of this entry placed at [assignedRank] on a board.
  ///
  /// [assignedRank] must be a positive 1-based position — assigning `0` or a
  /// negative rank is an [ErrorKind.invariant] failure so a mis-built board
  /// can never silently ship an unplaced or nonsensical line.
  Result<FixtureLeaderboardEntry> withRank(int assignedRank) {
    if (assignedRank < 1) {
      return const Result.err(
        AppError.invariant(
          'fixture_leaderboard.rank_not_positive',
          'A fixture leaderboard rank must be a positive 1-based position',
        ),
      );
    }
    return Result.ok(
      FixtureLeaderboardEntry._(
        participantId: participantId,
        totalPoints: totalPoints,
        fixturesScored: fixturesScored,
        rank: assignedRank,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FixtureLeaderboardEntry &&
      other.participantId == participantId &&
      other.totalPoints == totalPoints &&
      other.fixturesScored == fixturesScored &&
      other.rank == rank;

  @override
  int get hashCode =>
      Object.hash(participantId, totalPoints, fixturesScored, rank);

  @override
  String toString() =>
      'FixtureLeaderboardEntry(#$rank participant: ${participantId.value}, '
      'total: $totalPoints, fixturesScored: $fixturesScored)';
}
