import 'package:domain/src/competition/participant_id.dart';
import 'package:domain/src/competition/season_id.dart';
import 'package:domain/src/identity/user_id.dart';
import 'package:domain/src/leaderboard/fixture_leaderboard_entry.dart';
import 'package:domain/src/leaderboard/participant_fixture_totals.dart';
import 'package:domain/src/scoring/fixture_score_result.dart';
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
/// 2. [FixtureLeaderboardEntry.referralPoints] descending -- the month's
///    invitation points break a points tie and are never added to the
///    points (decided 2026-09-27, migration 0073);
/// 3. [FixtureLeaderboardEntry.exactCount] descending;
/// 4. participant id value ascending, for a stable display order only.
///
/// **Rank rule:** standard competition ("1224") ranking over steps 1-3:
/// entries level on points, invitation points AND exact scorelines share a
/// rank. The daily snapshot (migration 0074) ranks the same way.
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
    Map<String, int> previousRanks = const <String, int>{},
    Map<String, UserId> avatarUserIds = const <String, UserId>{},
    Map<String, DateTime> avatarUpdatedAt = const <String, DateTime>{},
  }) {
    final totals = <String, int>{};
    final counts = <String, int>{};
    final exact = <String, int>{};
    final decided = <String, int>{};
    final byId = <String, ParticipantId>{};

    for (final score in scores) {
      final key = score.participantId.value;
      totals[key] = (totals[key] ?? 0) + score.points;
      counts[key] = (counts[key] ?? 0) + 1;
      byId[key] = score.participantId;

      // Accuracy comes out of the rows already in hand -- the grade travels
      // with every score, so this costs no extra read and cannot disagree
      // with the total beside it.
      switch (score.result.grade) {
        case FixtureScoreGrade.exactScoreline:
          exact[key] = (exact[key] ?? 0) + 1;
          decided[key] = (decided[key] ?? 0) + 1;
        case FixtureScoreGrade.correctOutcome:
        case FixtureScoreGrade.incorrect:
          decided[key] = (decided[key] ?? 0) + 1;
        case FixtureScoreGrade.missed:
        case FixtureScoreGrade.pending:
          // Neither is a prediction that turned out wrong: `missed` means
          // none was made, `pending` means the match is not settled. Both
          // stay out of the denominator.
          break;
      }
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
          exactCount: exact[key] ?? 0,
          decidedCount: decided[key] ?? 0,
          // Absent from the snapshot means absent from the comparison: a
          // participant who first scored today gets no arrow rather than a
          // fabricated one.
          previousRank: previousRanks[key],
          // Absent from these maps means "no picture stored": the board draws
          // the participant's initial, which is a complete answer on its own
          // and never a failed image request.
          avatarUserId: avatarUserIds[key],
          avatarUpdatedAt: avatarUpdatedAt[key],
        ),
    ]..sort(_compare);

    final ranked = <FixtureLeaderboardEntry>[];
    for (var i = 0; i < ordered.length; i++) {
      final entry = ordered[i];
      final int position = i + 1;
      final int assigned;
      if (i > 0 && _level(ordered[i - 1], entry)) {
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
  /// Builds the same ranked board from [totals] the store already summed per
  /// participant -- the production path, so the individual score rows never
  /// leave the database. Ordering, tie-breaks and ranks are exactly
  /// [rank]'s. A participant listed twice is an invariant breach (the store
  /// groups by participant), never silently merged.
  static Result<FixtureLeaderboard> rankTotals({
    required SeasonId seasonId,
    required List<ParticipantFixtureTotals> totals,
    required Map<String, String> displayNames,
    Map<String, int> previousRanks = const <String, int>{},
    Map<String, UserId> avatarUserIds = const <String, UserId>{},
    Map<String, DateTime> avatarUpdatedAt = const <String, DateTime>{},
    bool breakTiesByReferrals = true,
  }) {
    final seen = <String>{};
    for (final line in totals) {
      if (!seen.add(line.participantId.value)) {
        return Result.err(
          AppError.invariant(
            'fixture_leaderboard.duplicate_participant',
            'Participant ${line.participantId.value} appears more than once '
                'in the fixture totals',
          ),
        );
      }
    }

    final ordered = <FixtureLeaderboardEntry>[
      for (final line in totals)
        FixtureLeaderboardEntry.aggregate(
          participantId: line.participantId,
          displayName: displayNames[line.participantId.value] ?? '?',
          totalPoints: line.totalPoints,
          fixturesScored: line.fixturesScored,
          exactCount: line.exactCount,
          decidedCount: line.decidedCount,
          referralPoints: breakTiesByReferrals ? line.referralPoints : 0,
          previousRank: previousRanks[line.participantId.value],
          avatarUserId: avatarUserIds[line.participantId.value],
          avatarUpdatedAt: avatarUpdatedAt[line.participantId.value],
        ),
    ]..sort(_compare);

    final ranked = <FixtureLeaderboardEntry>[];
    for (var i = 0; i < ordered.length; i++) {
      final entry = ordered[i];
      final int assigned = i > 0 && _level(ordered[i - 1], entry)
          ? ranked[i - 1].rank
          : i + 1;
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

  static int _compare(FixtureLeaderboardEntry a, FixtureLeaderboardEntry b) {
    final byPoints = b.totalPoints.compareTo(a.totalPoints);
    if (byPoints != 0) {
      return byPoints;
    }
    final byReferrals = b.referralPoints.compareTo(a.referralPoints);
    if (byReferrals != 0) {
      return byReferrals;
    }
    final byExact = b.exactCount.compareTo(a.exactCount);
    if (byExact != 0) {
      return byExact;
    }
    return a.participantId.value.compareTo(b.participantId.value);
  }

  /// Whether two neighbours share a rank: level on points, invitation points
  /// and exact scorelines.
  static bool _level(FixtureLeaderboardEntry a, FixtureLeaderboardEntry b) =>
      a.totalPoints == b.totalPoints &&
      a.referralPoints == b.referralPoints &&
      a.exactCount == b.exactCount;

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
