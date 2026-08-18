import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/scoring/round_score.dart';
import 'package:shared/shared.dart';

/// One participant's line on a round leaderboard — a **read-side projection**
/// value, exactly like [LeaderboardEntry] and [HallOfFameEntry] but scoped to a
/// single round instead of a season or all-time (Axiom 5: still the SAME
/// points [RoundScore] already computed — this never computes or stores a
/// point total of its own).
///
/// It names the [participantId] by id only and carries [totalPoints] echoed
/// straight from the round's already-computed [RoundScore.totalPoints]. There
/// is no `entryCount`/`joinedAt` analogue here (unlike [LeaderboardEntry]): a
/// round score is a single already-summed value, not an aggregate over
/// multiple ledger movements, and a round has no natural "joined at" instant
/// of its own.
///
/// [rank] is the standard-competition ("1224") rank on the board, assigned by
/// [RoundLeaderboard.rank] over the fully ordered entries — never computed by
/// this value in isolation.
///
/// Points here are a server-computed read value (Axiom 2: the client never
/// computes or submits a point amount). Pure and immutable; value-comparable
/// by all fields.
final class RoundLeaderboardEntry {
  const RoundLeaderboardEntry._({
    required this.participantId,
    required this.totalPoints,
    required this.rank,
  });

  /// Builds an **unranked** entry from one participant's already-computed
  /// [RoundScore]. The [rank] is left `0` (unassigned) — a meaningful rank
  /// exists only relative to the whole ordered board, so it is assigned later
  /// by [RoundLeaderboard.rank]. Always succeeds: [RoundScore] has already
  /// validated everything this entry echoes.
  factory RoundLeaderboardEntry.fromScore(RoundScore score) {
    return RoundLeaderboardEntry._(
      participantId: score.participantId,
      totalPoints: score.totalPoints,
      rank: _unassignedRank,
    );
  }

  /// The sentinel rank of an entry that has not yet been placed on a board.
  static const int _unassignedRank = 0;

  /// The participant this line belongs to (by id).
  final ParticipantId participantId;

  /// The round's already-computed total for this participant (echoed from
  /// [RoundScore.totalPoints] — never recomputed here).
  final int totalPoints;

  /// The participant's standard-competition ("1224") rank on the board, or `0`
  /// while unassigned. Assigned by [RoundLeaderboard].
  final int rank;

  /// Whether this entry has been placed on a board (has a meaningful [rank]).
  bool get isRanked => rank != _unassignedRank;

  /// Returns a copy of this entry placed at [assignedRank] on a board.
  ///
  /// [assignedRank] must be a positive 1-based position — assigning `0` or a
  /// negative rank is an [ErrorKind.invariant] failure so a mis-built board
  /// can never silently ship an unplaced or nonsensical line.
  Result<RoundLeaderboardEntry> withRank(int assignedRank) {
    if (assignedRank < 1) {
      return const Result.err(
        AppError.invariant(
          'round_leaderboard.rank_not_positive',
          'A round leaderboard rank must be a positive 1-based position',
        ),
      );
    }
    return Result.ok(
      RoundLeaderboardEntry._(
        participantId: participantId,
        totalPoints: totalPoints,
        rank: assignedRank,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoundLeaderboardEntry &&
      other.participantId == participantId &&
      other.totalPoints == totalPoints &&
      other.rank == rank;

  @override
  int get hashCode => Object.hash(participantId, totalPoints, rank);

  @override
  String toString() =>
      'RoundLeaderboardEntry(#$rank participant: ${participantId.value}, '
      'total: $totalPoints)';
}
