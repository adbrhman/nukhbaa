import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/identity/user_id.dart';
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
    required this.displayName,
    required this.totalPoints,
    required this.fixturesScored,
    required this.exactCount,
    required this.decidedCount,
    required this.previousRank,
    required this.avatarUserId,
    required this.avatarUpdatedAt,
    required this.rank,
  });

  /// Builds an **unranked** entry from a participant's already-summed
  /// [totalPoints] and how many fixtures ([fixturesScored]) contributed to
  /// it. The [rank] is left `0` (unassigned) — a meaningful rank exists only
  /// relative to the whole ordered board, so it is assigned later by
  /// `FixtureLeaderboard.rank`.
  factory FixtureLeaderboardEntry.aggregate({
    required ParticipantId participantId,
    required String displayName,
    required int totalPoints,
    required int fixturesScored,
    int exactCount = 0,
    int decidedCount = 0,
    int? previousRank,
    UserId? avatarUserId,
    DateTime? avatarUpdatedAt,
  }) {
    return FixtureLeaderboardEntry._(
      participantId: participantId,
      displayName: displayName,
      totalPoints: totalPoints,
      fixturesScored: fixturesScored,
      exactCount: exactCount,
      decidedCount: decidedCount,
      previousRank: previousRank,
      avatarUserId: avatarUserId,
      avatarUpdatedAt: avatarUpdatedAt,
      rank: _unassignedRank,
    );
  }

  /// The sentinel rank of an entry that has not yet been placed on a board.
  static const int _unassignedRank = 0;

  /// The participant this line belongs to (by id).
  final ParticipantId participantId;

  /// The platform-owned display name of the user behind this participant
  /// (`identity.users.display_name`), so the leaderboard shows a real name
  /// instead of a raw id.
  final String displayName;

  /// The running total of every fixture score this participant has been
  /// awarded so far this season (never recomputed here).
  final int totalPoints;

  /// How many of the season's fixtures have been scored for this participant
  /// so far — an audit/transparency count for the live/partial board (a
  /// season with unscored fixtures remaining is a normal, ongoing state,
  /// never an error).
  final int fixturesScored;

  /// How many of the participant's decided fixtures they called EXACTLY right
  /// (`exactScoreline`). The numerator of [accuracy]: a merely correct outcome
  /// earns points but did not get the score right, so it is not accuracy.
  final int exactCount;

  /// How many fixtures were actually DECIDED for this participant --
  /// `exactScoreline`, `correctOutcome` or `incorrect`.
  ///
  /// Narrower than [fixturesScored] on purpose. That count includes `missed`
  /// (the fixture kicked off before they predicted it) and `pending` (the
  /// result is not in yet). Neither is a prediction that turned out wrong:
  /// counting a missed fixture against accuracy would measure attendance, and
  /// counting a pending one would let a figure drop for a match still being
  /// played. The denominator is therefore predictions actually made and
  /// actually settled.
  final int decidedCount;

  /// The share of decided fixtures called exactly right, in `0.0..1.0`, or
  /// `null` when nothing has been decided yet. A participant with no decided
  /// fixture has NO accuracy -- not zero accuracy -- so the absence is
  /// modelled as null rather than a misleading 0%.
  double? get accuracy => decidedCount <= 0 ? null : exactCount / decidedCount;

  /// The rank this participant held at the season's most recent daily
  /// snapshot, or `null` when there is nothing to compare against -- no
  /// capture has run yet, or they were not on the board when it did.
  ///
  /// Read from the snapshot, never derived: the application layer cannot
  /// forge a past rank, because a fabricated one would produce an arrow no
  /// participant earned.
  final int? previousRank;

  /// The user behind this participant, carried ONLY when they have a stored
  /// profile picture -- null otherwise. Together with [avatarUpdatedAt] it is
  /// everything needed to address that picture; the URL itself is built at the
  /// HTTP edge, which is the only layer that owns the route shape.
  final UserId? avatarUserId;

  /// When that picture was last replaced -- the cache-busting version. Null
  /// exactly when [avatarUserId] is null: the pair is stored together and is
  /// meaningful only together.
  final DateTime? avatarUpdatedAt;

  /// Whether this participant has a profile picture to draw at all.
  bool get hasAvatar => avatarUserId != null && avatarUpdatedAt != null;

  /// How many places the participant has climbed since [previousRank]:
  /// positive is up, negative is down, `0` is unchanged, `null` is nothing to
  /// compare against. Computed only once [rank] is assigned, so the arrow can
  /// never disagree with the place printed beside it.
  int? get movement =>
      previousRank == null || !isRanked ? null : previousRank! - rank;

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
        displayName: displayName,
        totalPoints: totalPoints,
        fixturesScored: fixturesScored,
        exactCount: exactCount,
        decidedCount: decidedCount,
        previousRank: previousRank,
        avatarUserId: avatarUserId,
        avatarUpdatedAt: avatarUpdatedAt,
        rank: assignedRank,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FixtureLeaderboardEntry &&
      other.participantId == participantId &&
      other.displayName == displayName &&
      other.totalPoints == totalPoints &&
      other.fixturesScored == fixturesScored &&
      other.exactCount == exactCount &&
      other.decidedCount == decidedCount &&
      other.previousRank == previousRank &&
      other.avatarUserId == avatarUserId &&
      other.avatarUpdatedAt == avatarUpdatedAt &&
      other.rank == rank;

  @override
  int get hashCode => Object.hash(
    participantId,
    displayName,
    totalPoints,
    fixturesScored,
    exactCount,
    decidedCount,
    previousRank,
    avatarUserId,
    avatarUpdatedAt,
    rank,
  );

  @override
  String toString() =>
      'FixtureLeaderboardEntry(#$rank participant: ${participantId.value}, '
      'total: $totalPoints, fixturesScored: $fixturesScored)';
}
