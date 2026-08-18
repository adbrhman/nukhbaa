import 'package:domain/src/competition/round_id.dart';
import 'package:domain/src/leaderboard/round_leaderboard_entry.dart';
import 'package:domain/src/scoring/round_score.dart';
import 'package:shared/shared.dart';

/// A round's ranked standings — the read-side projection of that round's
/// already-computed [RoundScore]s (Leaderboards architecture decision in
/// project-context §2, extended to a per-round scope; Axiom 5: still the SAME
/// points Scoring already produced — this never re-computes a point value,
/// only orders and ranks what Scoring already produced).
///
/// A [RoundLeaderboard] is a pure, ordered, immutable list of
/// [RoundLeaderboardEntry], one per participant scored in the round, sorted by
/// the total order below and carrying a **standard competition ("1224")
/// rank** — mirroring [SeasonLeaderboard] and [HallOfFame] exactly. The
/// participant ranked #1 is the round's informal "round king"; this aggregate
/// only ranks — the UI decides how to highlight that.
///
/// **Total order (deterministic, reproducible — never arbitrary DB order):**
/// 1. [RoundLeaderboardEntry.totalPoints] descending;
/// 2. tie-break: [ParticipantId] value ascending — a round has no natural
///    "joined at" instant of its own (unlike a season board), so the id is the
///    sole, deterministic tie-break, exactly like [HallOfFame].
///
/// **Rank rule:** identical to [SeasonLeaderboard]/[HallOfFame] — standard
/// competition ("1224") ranking: equal totals share a rank, the next distinct
/// total skips by the number tied.
final class RoundLeaderboard {
  const RoundLeaderboard._({required this.roundId, required this.entries});

  /// Builds a ranked leaderboard for [roundId] from every participant's
  /// already-computed [scores] (typically the same [RoundScore] list
  /// `GetRoundScores` reads — the SAME already-scored round, never re-scored
  /// here).
  ///
  /// The result is total and deterministic: the same set of scores always
  /// yields the same ordered, ranked board. Steps:
  /// 1. reject a duplicate participant (a score set must carry each
  ///    participant at most once — a repeated participant would double-count
  ///    and corrupt the standings, an [ErrorKind.invariant] failure);
  /// 2. sort by the [RoundLeaderboard] total order (points desc, id asc);
  /// 3. assign standard-competition ("1224") ranks.
  ///
  /// An empty [scores] yields an empty board (a scored round nobody
  /// predicted — a legitimate empty result, not an error).
  static Result<RoundLeaderboard> rank({
    required RoundId roundId,
    required List<RoundScore> scores,
  }) {
    final seen = <String>{};
    for (final score in scores) {
      if (!seen.add(score.participantId.value)) {
        return Result.err(
          AppError.invariant(
            'round_leaderboard.duplicate_participant',
            'Participant ${score.participantId.value} appears more than '
                'once in the round score set',
          ),
        );
      }
    }

    // Copy before sorting — never mutate the caller's list.
    final ordered = <RoundLeaderboardEntry>[
      for (final score in scores) RoundLeaderboardEntry.fromScore(score),
    ]..sort(_compare);

    final ranked = <RoundLeaderboardEntry>[];
    for (var i = 0; i < ordered.length; i++) {
      final entry = ordered[i];
      final int position = i + 1;
      final int assigned;
      if (i > 0 && ordered[i - 1].totalPoints == entry.totalPoints) {
        assigned = ranked[i - 1].rank;
      } else {
        assigned = position;
      }
      final placed = entry.withRank(assigned);
      if (placed is Err<RoundLeaderboardEntry>) {
        return Result.err(placed.error);
      }
      ranked.add((placed as Ok<RoundLeaderboardEntry>).value);
    }

    return Result.ok(
      RoundLeaderboard._(
        roundId: roundId,
        entries: List<RoundLeaderboardEntry>.unmodifiable(ranked),
      ),
    );
  }

  /// The total order over entries: points descending, then participant id
  /// ascending (a stable, total tie-break).
  static int _compare(RoundLeaderboardEntry a, RoundLeaderboardEntry b) {
    final byPoints = b.totalPoints.compareTo(a.totalPoints);
    if (byPoints != 0) {
      return byPoints;
    }
    return a.participantId.value.compareTo(b.participantId.value);
  }

  /// The round these standings are for.
  final RoundId roundId;

  /// The ranked entries in display order (total order above). Always an
  /// unmodifiable list; every entry carries a meaningful
  /// ([RoundLeaderboardEntry.rank] >= 1) rank.
  final List<RoundLeaderboardEntry> entries;

  /// How many participants the board ranks.
  int get size => entries.length;

  @override
  bool operator ==(Object other) =>
      other is RoundLeaderboard &&
      other.roundId == roundId &&
      _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(roundId, Object.hashAll(entries));

  @override
  String toString() =>
      'RoundLeaderboard(round: ${roundId.value}, ${entries.length} entries)';

  static bool _listEquals(
    List<RoundLeaderboardEntry> a,
    List<RoundLeaderboardEntry> b,
  ) {
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
