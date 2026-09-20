import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port for the weekly league's seats (P2-3).
///
/// Backed by `PostgresWeeklyLeagueRepository`. It stores and finds seats; it
/// decides nothing. Which tier a player belongs in, how large a group may be
/// and who moves at the end of the week are all `WeeklyLeaguePolicy`, in
/// Dart, where they are tested without a database.
///
/// General contract (Application ADR, Section 2): MUST NOT throw -- every
/// outcome is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class WeeklyLeagueRepository {
  /// The seat [userId] holds in the week opened by [weekStart], or null when
  /// they have not been placed yet.
  ///
  /// [weekStart] is a Monday as a UTC midnight, as `WeeklyLeaguePolicy`
  /// produces.
  Future<Result<WeeklyLeagueSeat?>> seatFor({
    required UserId userId,
    required DateTime weekStart,
  });

  /// Places [userId] in the least-full group of [tier] for [weekStart],
  /// opening a new group with [newLeagueId] and [capacity] when every
  /// existing group of that tier is full.
  ///
  /// Idempotent and safe under concurrency: the caller that loses the race
  /// receives the seat the winner wrote, never a second one. That guarantee
  /// rests on `weekly_league_members_week_user_uniq` (migration 0061), not
  /// on the order of these statements.
  Future<Result<WeeklyLeagueSeat>> place({
    required UserId userId,
    required DateTime weekStart,
    required WeeklyLeagueTier tier,
    required WeeklyLeagueId newLeagueId,
    required int capacity,
  });

  /// How [userId]'s most recently judged week ended, or null when no week of
  /// theirs has been judged.
  ///
  /// Read from the newest `weekly_league_finished` event in
  /// `gamification.events`: the closing job writes the standing there, so
  /// the ladder needs no table of its own and a corrected result cannot
  /// silently rewrite a tier that was already awarded.
  Future<Result<WeeklyLeagueFinish?>> lastFinishOf({required UserId userId});
}

/// A player's seat in one week's group.
final class WeeklyLeagueSeat {
  /// Creates a seat.
  const WeeklyLeagueSeat({
    required this.leagueId,
    required this.weekStart,
    required this.tier,
    required this.groupIndex,
    required this.joinedAt,
  });

  /// The group this seat belongs to.
  final WeeklyLeagueId leagueId;

  /// The Monday that opens the week, as a UTC midnight.
  final DateTime weekStart;

  /// The tier the group plays in.
  final WeeklyLeagueTier tier;

  /// 0-based position of the group among the groups of its tier and week.
  final int groupIndex;

  /// When the seat was taken. The third tie-break of the week.
  final DateTime joinedAt;
}

/// How a judged week ended for one player.
final class WeeklyLeagueFinish {
  /// Creates a finish.
  const WeeklyLeagueFinish({required this.tier, required this.outcome});

  /// The tier that week was played in.
  final WeeklyLeagueTier tier;

  /// Where that week sent the player.
  final WeeklyLeagueOutcome outcome;
}
