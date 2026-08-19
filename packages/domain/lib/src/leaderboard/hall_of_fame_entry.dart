import 'package:domain/src/identity/user_id.dart';
import 'package:shared/shared.dart';

/// One user's line on the platform-wide, all-time Hall of Fame — a **read-side
/// projection** value, exactly like [LeaderboardEntry] but aggregated ACROSS
/// every season rather than scoped to one (Axiom 5: still the SAME append-only
/// ledger, no new points source, no per-season re-computation of truth).
///
/// It names the [userId] (not a [ParticipantId] — a user may hold a different
/// participant per season, so the Hall of Fame aggregates by the platform
/// identity that is constant across seasons) and carries [totalPoints] (the
/// signed SUM of every ledger `amount` across all of that user's participant
/// rows) and [seasonsPlayed] (how many distinct seasons contributed to that
/// total — audit/traceability, mirroring [LeaderboardEntry.entryCount]).
///
/// [rank] is the standard-competition (\"1224\") rank on the board, assigned by
/// [HallOfFame.rank] over the fully ordered entries — never computed by this
/// value in isolation.
///
/// Points here are a server-computed read value (Axiom 2: the client never
/// computes or submits a point amount). Pure and immutable; value-comparable by
/// all fields.
final class HallOfFameEntry {
  const HallOfFameEntry._({
    required this.userId,
    required this.displayName,
    required this.totalPoints,
    required this.seasonsPlayed,
    required this.rank,
  });

  /// Builds an **unranked** entry from an aggregated cross-season ledger
  /// projection for one user. The [rank] is left `0` (unassigned) — a
  /// meaningful rank exists only relative to the whole ordered board, so it is
  /// assigned later by [HallOfFame.rank].
  ///
  /// Enforced invariant (kept total — no exception escapes a query path):
  /// [seasonsPlayed] must be non-negative (a count of seasons contributed to).
  /// [totalPoints] is intentionally unconstrained in sign, exactly like
  /// [LeaderboardEntry.totalPoints] (a correction may net a user negative).
  static Result<HallOfFameEntry> projected({
    required UserId userId,
    required String displayName,
    required int totalPoints,
    required int seasonsPlayed,
  }) {
    if (seasonsPlayed < 0) {
      return const Result.err(
        AppError.invariant(
          'hall_of_fame.seasons_played_negative',
          'A Hall of Fame entry cannot count a negative number of seasons',
        ),
      );
    }
    return Result.ok(
      HallOfFameEntry._(
        userId: userId,
        displayName: displayName,
        totalPoints: totalPoints,
        seasonsPlayed: seasonsPlayed,
        rank: _unassignedRank,
      ),
    );
  }

  /// The sentinel rank of an entry that has not yet been placed on a board.
  static const int _unassignedRank = 0;

  /// The user this line belongs to (by id) — constant across seasons, unlike a
  /// per-season [ParticipantId].
  final UserId userId;

  /// The user's platform-owned display name (from `identity.users`), shown on
  /// the board instead of the raw [userId].
  final String displayName;

  /// The signed SUM of the user's ledger `amount`s across every season they
  /// have participated in.
  final int totalPoints;

  /// How many distinct seasons contributed to [totalPoints] (audit).
  final int seasonsPlayed;

  /// The user's standard-competition (\"1224\") rank on the board, or `0` while
  /// unassigned. Assigned by [HallOfFame].
  final int rank;

  /// Whether this entry has been placed on a board.
  bool get isRanked => rank != _unassignedRank;

  /// Returns a copy of this entry placed at [assignedRank] on a board.
  Result<HallOfFameEntry> withRank(int assignedRank) {
    if (assignedRank < 1) {
      return const Result.err(
        AppError.invariant(
          'hall_of_fame.rank_not_positive',
          'A Hall of Fame rank must be a positive 1-based position',
        ),
      );
    }
    return Result.ok(
      HallOfFameEntry._(
        userId: userId,
        displayName: displayName,
        totalPoints: totalPoints,
        seasonsPlayed: seasonsPlayed,
        rank: assignedRank,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HallOfFameEntry &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.totalPoints == totalPoints &&
      other.seasonsPlayed == seasonsPlayed &&
      other.rank == rank;

  @override
  int get hashCode =>
      Object.hash(userId, displayName, totalPoints, seasonsPlayed, rank);

  @override
  String toString() =>
      'HallOfFameEntry(#$rank user: ${userId.value} "$displayName", '
      'total: $totalPoints, seasons: $seasonsPlayed)';
}
