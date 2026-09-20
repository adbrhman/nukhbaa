import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port: which weekly-league weeks are waiting to be judged (P2-5).
///
/// Backed by `PostgresWeeklyLeagueClosureStore` over
/// `gamification.weekly_leagues` and `gamification.weekly_league_closures`
/// (migration 0061). It lists and marks; it judges nothing. Who ranks where
/// is `WeeklyLeaguePolicy`, and the standing itself is the
/// `weekly_league_finished` events the closing use-case writes, not a row
/// here.
///
/// A week is CLOSED when it has a row in `weekly_league_closures`. That row
/// is the watermark that stops the job from judging the same week twice, in
/// the way `gamification.settled_days` does for match days.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class WeeklyLeagueClosureStore {
  /// The Monday of the OLDEST week that has at least one group and is not
  /// closed yet, as a UTC midnight, or `null` when every week that has a
  /// group is closed.
  ///
  /// It says nothing about whether the week has ENDED: the week in progress
  /// has groups and no closure too. Deciding when a week is due is the
  /// caller's clock, not the store's.
  ///
  /// Oldest first, so a missed run is made good in order: an earlier week's
  /// tiers must exist before a later week is judged.
  Future<Result<DateTime?>> nextUnclosedWeek();

  /// The groups formed for the week opened by [weekStart], each with the
  /// tier it played in. Empty when the week has none.
  ///
  /// [weekStart] is a Monday as a UTC midnight, as `WeeklyLeaguePolicy`
  /// produces.
  Future<Result<List<WeeklyLeagueGroupRef>>> groupsOf(DateTime weekStart);

  /// Records that the week opened by [weekStart] has been judged, with the
  /// number of members that were.
  ///
  /// Insert-only and idempotent: closing a week that is already closed
  /// changes nothing and still returns `Ok`. The table rejects UPDATE and
  /// DELETE for every role, so a mark cannot be taken back.
  Future<Result<void>> markClosed({
    required DateTime weekStart,
    required int memberCount,
  });
}

/// One group of a week, as the closing job needs to see it: which group it
/// is and the tier it played in.
final class WeeklyLeagueGroupRef {
  /// Creates a group reference.
  const WeeklyLeagueGroupRef({required this.leagueId, required this.tier});

  /// The group.
  final WeeklyLeagueId leagueId;

  /// The tier the group played in that week.
  final WeeklyLeagueTier tier;
}
