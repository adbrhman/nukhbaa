import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/competition/season_id.dart';
import 'package:domain/src/leaderboard/fixture_leaderboard_entry.dart';
import 'package:domain/src/scoring/participant_fixture_score.dart';
import 'package:shared/shared.dart';

/// A season's ranked standings over its **individually-scored fixtures** —
/// the live, "monthly" leaderboard under Axiom 4 Amendment ("ScoreFixture
/// replaces ScoreRound"; there is no round left to rank within, so this
/// aggregates every already-computed `ParticipantFixtureScore` for the
/// fixtures linked to the season instead — Axiom 5: still the SAME points
/// already produced per fixture, this never re-computes a point value, only
/// sums and ranks what Scoring already produced).
///
/// Unlike `RoundLeaderboard.rank` (which ranks one already-summed
/// `RoundScore` per participant), `FixtureLeaderboard.rank` first
/// **aggregates**: every `ParticipantFixtureScore` for the season's fixtures
/// is grouped by participant and summed into a running total. This is what
/// makes the board **live/partial** by construction — a participant with
/// fewer fixtures scored so far still gets a total from whatever has already
/// landed; there is no "the season isn't finished yet" gate here.
///
/// **Total order (deterministic, reproducible — never arbitrary DB order):**
/// 1. [FixtureLeaderboardEntry.totalPoints] descending;
/// 2. tie-break: participant id value ascending — mirrors `RoundLeaderboard`.
///
/// **Rank rule:** identical to `RoundLeaderboard`/`SeasonLeaderboard` —
/// standard competition ("1224") ranking.
final class FixtureLeaderboard {
  const FixtureLeaderboard._({required this.seasonId, required this.entries});

  /// Builds a ranked leaderboard for [seasonId] by aggregating every
  /// already-computed `ParticipantFixtureScore` in [scores] (typically every
  /// score for every fixture linked to the season — the same rows
  /// `GetSeasonFixtureLeaderboard` reads).
  ///
  /// A participant may legitimately appear more than once in [scores] (one
  /// row per fixture they've been scored on) — unlike `RoundLeaderboard.rank`,
  /// this is expected, not an invariant violation; the rows are summed per
  /// participant before ranking. An empty [scores] yields an empty board (no
  /// fixture scored yet — a legitimate live/partial state, not an error).
  static Result<FixtureLeaderboard> rank({
    required SeasonId seasonId,
    required List<ParticipantFixtureScore> scores,
    required Map<String, String> displayNames,
  }) {
    final totals = <String, int>{};
    final counts = <String, int>{};
    final byId = <String, ParticipantId>{};

    for (final score in scores) {
      final key = score.participantId.value;
      totals[key] = (totals[key] ?? 0) + score.points;
      counts[key] = (counts[key] ?? 0) + 1;
      byId[key] = score.participantId;
    }

    // Copy before sorting — never mutate the caller's list.
    final ordered = <FixtureLeaderboardEntry>[
      for (final key in totals.keys)
        FixtureLeaderboardEntry.aggregate(
          participantId: byId[key]!,
          // A participant somehow missing a resolved name (never expected —
          // every participant has a backing user row) still renders instead
          // of throwing (Application ADR §2: total, no exception escapes a
          // query path).
          displayName: displayNames[key] ?? '?',
          totalPoints: totals[key]!,
          fixturesScored: counts[key]!,
        ),
    ]..sort(_compare);

    final ranked = <FixtureLeaderboardEntry>[];
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
      if (placed is Err<FixtureLeaderboardEntry>) {
        return Result.err(placed.error);
      }
      ranked.add((placed as Ok<FixtureLeaderboardEntry>).value);
    }

    return Result.ok(
      FixtureLeaderboard._(
        seasonId: seasonId,
        entries: List<FixtureLeaderboardEntry>.unmodifiable(ranked),
      ),
    );
  }

  /// The total order over entries: points descending, then participant id
  /// ascending (a stable, total tie-break).
  static int _compare(FixtureLeaderboardEntry a, FixtureLeaderboardEntry b) {
    final byPoints = b.totalPoints.compareTo(a.totalPoints);
    if (byPoints != 0) {
      return byPoints;
    }
    return a.participantId.value.compareTo(b.participantId.value);
  }

  /// The season these standings are for.
  final SeasonId seasonId;

  /// The ranked entries in display order (total order above). Always an
  /// unmodifiable list; every entry carries a meaningful
  /// (`FixtureLeaderboardEntry.rank` >= 1) rank.
  final List<FixtureLeaderboardEntry> entries;

  /// How many participants the board ranks.
  int get size => entries.length;

  @override
  bool operator ==(Object other) =>
      other is FixtureLeaderboard &&
      other.seasonId == seasonId &&
      _listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(seasonId, Object.hashAll(entries));

  @override
  String toString() =>
      'FixtureLeaderboard(season: ${seasonId.value}, '
      '${entries.length} entries)';

  static bool _listEquals(
    List<FixtureLeaderboardEntry> a,
    List<FixtureLeaderboardEntry> b,
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
