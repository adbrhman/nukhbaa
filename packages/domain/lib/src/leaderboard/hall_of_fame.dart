import 'package:domain/src/leaderboard/hall_of_fame_entry.dart';
import 'package:shared/shared.dart';

/// The platform-wide, all-time standings — the read-side projection of the
/// append-only ledger aggregated ACROSS every season (Leaderboards
/// architecture decision: the season board is the canonical *scoped* ranking
/// context; the Hall of Fame is its all-time counterpart over the SAME ledger,
/// never a second source of truth for points — Axiom 5).
///
/// A [HallOfFame] is a pure, ordered, immutable list of [HallOfFameEntry],
/// one per user who has ever earned a ledger movement, sorted by the same
/// kind of total order as [SeasonLeaderboard] and carrying a standard
/// competition (\"1224\") rank.
///
/// **Total order:**
/// 1. [HallOfFameEntry.totalPoints] descending;
/// 2. tie-break: [UserId] value ascending (a stable, total order — unlike a
///    season board there is no natural \"joined at\" instant shared by every
///    season a user has played, so the id is the sole, deterministic
///    tie-break).
///
/// **Rank rule:** identical to [SeasonLeaderboard] — standard competition
/// (\"1224\") ranking; equal totals share a rank, the next distinct total skips.
final class HallOfFame {
  const HallOfFame._({required this.entries});

  /// Builds a ranked Hall of Fame from the [projections] (one unranked
  /// [HallOfFameEntry] per user with at least one ledger movement).
  ///
  /// Rejects a duplicate [UserId] as an [ErrorKind.invariant] failure (a
  /// projection must carry each user at most once). An empty [projections]
  /// yields an empty board (a legitimate result before anyone has ever been
  /// credited).
  static Result<HallOfFame> rank({required List<HallOfFameEntry> projections}) {
    final seen = <String>{};
    for (final entry in projections) {
      if (!seen.add(entry.userId.value)) {
        return Result.err(
          AppError.invariant(
            'hall_of_fame.duplicate_user',
            'User ${entry.userId.value} appears more than once in the Hall '
                'of Fame projection',
          ),
        );
      }
    }

    final ordered = List<HallOfFameEntry>.of(projections)..sort(_compare);

    final ranked = <HallOfFameEntry>[];
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
      if (placed is Err<HallOfFameEntry>) {
        return Result.err(placed.error);
      }
      ranked.add((placed as Ok<HallOfFameEntry>).value);
    }

    return Result.ok(
      HallOfFame._(entries: List<HallOfFameEntry>.unmodifiable(ranked)),
    );
  }

  static int _compare(HallOfFameEntry a, HallOfFameEntry b) {
    final byPoints = b.totalPoints.compareTo(a.totalPoints);
    if (byPoints != 0) {
      return byPoints;
    }
    return a.userId.value.compareTo(b.userId.value);
  }

  /// The ranked entries in display order. Always an unmodifiable list; every
  /// entry carries a meaningful rank (>= 1).
  final List<HallOfFameEntry> entries;

  /// How many users the board ranks.
  int get size => entries.length;

  @override
  bool operator ==(Object other) =>
      other is HallOfFame && _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'HallOfFame(${entries.length} entries)';

  static bool _listEquals(List<HallOfFameEntry> a, List<HallOfFameEntry> b) {
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
