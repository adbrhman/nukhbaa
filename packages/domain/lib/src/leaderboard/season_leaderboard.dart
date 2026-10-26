import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/competition/season_id.dart';
import 'package:domain/src/leaderboard/leaderboard_entry.dart';
import 'package:shared/shared.dart';

/// A season's ranked standings — the read-side projection of the append-only
/// ledger for a single [CompetitionSeason] (Axiom 4: predict once, rank
/// everywhere; the season is the first and canonical ranking context — see the
/// Leaderboards architecture decision in project-context §2).
///
/// A [SeasonLeaderboard] is a pure, ordered, immutable list of
/// [LeaderboardEntry]s, one per participant of the season, sorted by the total
/// order defined below and carrying a **standard competition ("1224") rank**.
/// It is a *projection*: it holds no points of its own and is never a source of
/// truth — every [LeaderboardEntry.totalPoints] is a SUM already produced by the
/// ledger (Axiom 5). Building one from raw aggregated projections and ranking
/// them is the whole of the domain's Leaderboards responsibility; where the
/// totals come from (a live ledger view) is Infrastructure's concern.
///
/// **Total order (deterministic, reproducible — never arbitrary DB order),
/// the month board's chain (batch 129, applied here in batch 134):**
/// 1. [LeaderboardEntry.totalPoints] descending (more points ranks higher);
/// 2. [LeaderboardEntry.exactCount] descending;
/// 3. [LeaderboardEntry.outcomeCount] descending;
/// 4. [LeaderboardEntry.joinedAt] ascending (the earlier joiner first);
/// 5. final tie-break: [ParticipantId] value ascending, for a stable display
///    order only.
///
/// **Rank rule:** entries share a rank (and the next skips, "1224") only
/// when level on keys 1-4. Real players never join at the same instant, so
/// every player gets a place of his own, as on the month board -- the same
/// month read from the match card no longer shows three players tenth.
final class SeasonLeaderboard {
  const SeasonLeaderboard._({required this.seasonId, required this.entries});

  /// Builds a ranked leaderboard for [seasonId] from the [projections] (one
  /// unranked [LeaderboardEntry] per season participant — typically the output
  /// of the ledger projection adapter, or `LeaderboardEntry.projected`).
  ///
  /// The result is total and deterministic: the same set of projections always
  /// yields the same ordered, ranked board. Steps:
  /// 1. reject a duplicate [ParticipantId] (a projection must carry each
  ///    participant at most once — a repeated participant would double-count and
  ///    corrupt the standings, an [ErrorKind.invariant] failure — Axiom 5);
  /// 2. sort by the [SeasonLeaderboard] total order — the input order is
  ///    irrelevant, so an unordered DB read is ranked identically;
  /// 3. assign ranks: position 1-based, entries level on every ranking key
  ///    share the rank of the first of their group.
  ///
  /// An empty [projections] yields an empty board (a season with no participants
  /// — a legitimate empty result, not an error).
  static Result<SeasonLeaderboard> rank({
    required SeasonId seasonId,
    required List<LeaderboardEntry> projections,
  }) {
    final seen = <String>{};
    for (final entry in projections) {
      if (!seen.add(entry.participantId.value)) {
        return Result.err(
          AppError.invariant(
            'leaderboard.duplicate_participant',
            'Participant ${entry.participantId.value} appears more than once '
                'in the leaderboard projection',
          ),
        );
      }
    }

    // Copy before sorting — never mutate the caller's list.
    final ordered = List<LeaderboardEntry>.of(projections)..sort(_compare);

    final ranked = <LeaderboardEntry>[];
    for (var i = 0; i < ordered.length; i++) {
      final entry = ordered[i];
      // A participant level with the one before on every key shares its
      // rank; otherwise the rank is the 1-based position ("1224").
      final int position = i + 1;
      final int assigned;
      if (i > 0 && _level(ordered[i - 1], entry)) {
        assigned = ranked[i - 1].rank;
      } else {
        assigned = position;
      }
      final placed = entry.withRank(assigned);
      if (placed is Err<LeaderboardEntry>) {
        return Result.err(placed.error);
      }
      ranked.add((placed as Ok<LeaderboardEntry>).value);
    }

    return Result.ok(
      SeasonLeaderboard._(
        seasonId: seasonId,
        entries: List<LeaderboardEntry>.unmodifiable(ranked),
      ),
    );
  }

  /// The total order over entries (see the class comment).
  static int _compare(LeaderboardEntry a, LeaderboardEntry b) {
    // Points descending.
    final byPoints = b.totalPoints.compareTo(a.totalPoints);
    if (byPoints != 0) {
      return byPoints;
    }
    final byExact = b.exactCount.compareTo(a.exactCount);
    if (byExact != 0) {
      return byExact;
    }
    final byOutcome = b.outcomeCount.compareTo(a.outcomeCount);
    if (byOutcome != 0) {
      return byOutcome;
    }
    // joinedAt ascending (earlier joiner first).
    final byJoined = a.joinedAt.compareTo(b.joinedAt);
    if (byJoined != 0) {
      return byJoined;
    }
    // participant id ascending (final stable tie-break).
    return a.participantId.value.compareTo(b.participantId.value);
  }

  /// Whether two neighbours share a rank: level on every ranking key.
  static bool _level(LeaderboardEntry a, LeaderboardEntry b) =>
      a.totalPoints == b.totalPoints &&
      a.exactCount == b.exactCount &&
      a.outcomeCount == b.outcomeCount &&
      a.joinedAt == b.joinedAt;

  /// The season these standings are for.
  final SeasonId seasonId;

  /// The ranked entries in display order (total order above). Always an
  /// unmodifiable list; every entry carries a meaningful ([LeaderboardEntry.rank]
  /// >= 1) rank.
  final List<LeaderboardEntry> entries;

  /// How many participants the board ranks.
  int get size => entries.length;

  @override
  bool operator ==(Object other) =>
      other is SeasonLeaderboard &&
      other.seasonId == seasonId &&
      _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(seasonId, Object.hashAll(entries));

  @override
  String toString() =>
      'SeasonLeaderboard(season: ${seasonId.value}, ${entries.length} entries)';

  static bool _listEquals(List<LeaderboardEntry> a, List<LeaderboardEntry> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
