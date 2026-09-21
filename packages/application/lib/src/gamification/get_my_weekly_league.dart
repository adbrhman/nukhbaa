/// Use-case: read the caller's own weekly-league group (P2-4).
library;

import 'package:application/src/gamification/join_weekly_league.dart';
import 'package:application/src/gamification/ports/weekly_league_profile_reader.dart';
import 'package:application/src/gamification/ports/weekly_league_repository.dart';
import 'package:application/src/gamification/ports/weekly_league_standings_reader.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reads the standing of the group the caller plays in this week (P2-4).
///
/// **The read is what seats the player.** There is no Monday job that draws
/// the platform into groups (P2-3): a player takes a seat the first time
/// they are seen in the week, and looking at the league is such a sighting.
/// So this use-case asks [JoinWeeklyLeague] first -- idempotent, it returns
/// the seat a player already holds untouched -- and only then reads the
/// group. Nobody meets an empty league screen for want of a seat.
///
/// **It ranks; it does not score.** Each member's week arrives from
/// [WeeklyLeagueStandingsReader] as a [WeeklyLeagueEntry] already summed
/// from the one source of points, and the order is the policy's: the same
/// published total order the closing job judges with, so the place a player
/// reads on Tuesday is the place the week ends on if nothing changes, never
/// a second definition that can drift.
///
/// **Each row carries the outcome the week would give it if it closed now**,
/// taken from `WeeklyLeaguePolicy.judge`. The zero-points rule (nobody who
/// scored nothing is promoted) therefore stays with the policy that owns it
/// and is never re-derived in a client.
///
/// **Names are asked, not carried.** The policy ranks user ids and holds no
/// name, so each read asks [WeeklyLeagueProfileReader] once for exactly the
/// members it ranked and hands the answer back beside the placings. A
/// member the reader does not know stays on the table without a profile:
/// the standings are the answer, the name is only how a row is drawn. A
/// failure of the read itself is returned, not swallowed.
///
/// Only the caller's own group, always: there is no surface for reading
/// another one, so the principal is the whole of the authority check
/// ([JoinWeeklyLeague] enforces the role first).
///
/// Never throws; returns a typed [Result].
final class GetMyWeeklyLeague {
  /// Creates the use-case over its collaborators.
  const GetMyWeeklyLeague({
    required JoinWeeklyLeague join,
    required WeeklyLeagueStandingsReader standings,
    required WeeklyLeagueProfileReader profiles,
  }) : _join = join,
       _standings = standings,
       _profiles = profiles;

  final JoinWeeklyLeague _join;
  final WeeklyLeagueStandingsReader _standings;
  final WeeklyLeagueProfileReader _profiles;

  /// Reads [principal]'s group for the Riyadh week that is open now.
  Future<Result<MyWeeklyLeague>> call({
    required AuthenticatedUser principal,
  }) async {
    final seatResult = await _join(principal: principal);
    if (seatResult is Err<WeeklyLeagueSeat>) {
      return Result.err(seatResult.error);
    }
    final seat = (seatResult as Ok<WeeklyLeagueSeat>).value;

    final entriesResult = await _standings.entriesOf(
      leagueId: seat.leagueId,
      weekStart: seat.weekStart,
    );
    if (entriesResult is Err<List<WeeklyLeagueEntry>>) {
      return Result.err(entriesResult.error);
    }
    final entries = (entriesResult as Ok<List<WeeklyLeagueEntry>>).value;

    final placings = WeeklyLeaguePolicy.judge(
      tier: seat.tier,
      entries: entries,
    );

    var myRank = 0;
    for (final placing in placings) {
      if (placing.entry.userId == principal.userId) {
        myRank = placing.rank;
        break;
      }
    }
    if (myRank == 0) {
      // The caller holds a seat, so the group must list them. Answering
      // with a table that leaves the reader out would be a wrong answer
      // that looks right; a retryable error is the honest one.
      return const Result.err(
        AppError.transient(
          'gamification.weekly_league_member_missing',
          'The caller holds a weekly league seat but is absent from it',
        ),
      );
    }

    final profilesResult = await _profiles.profilesOf([
      for (final placing in placings) placing.entry.userId,
    ]);
    if (profilesResult is Err<Map<UserId, WeeklyLeagueMemberProfile>>) {
      return Result.err(profilesResult.error);
    }
    final profiles =
        (profilesResult as Ok<Map<UserId, WeeklyLeagueMemberProfile>>).value;

    final movement = WeeklyLeaguePolicy.movementCount(placings.length);
    return Result.ok(
      MyWeeklyLeague(
        seat: seat,
        readerId: principal.userId,
        placings: placings,
        profiles: profiles,
        myRank: myRank,
        promotionZone: seat.tier.canPromote ? movement : 0,
        relegationZone: seat.tier.canRelegate ? movement : 0,
      ),
    );
  }
}

/// The caller's weekly-league group, ranked.
final class MyWeeklyLeague {
  /// Creates a reading.
  const MyWeeklyLeague({
    required this.seat,
    required this.readerId,
    required this.placings,
    required this.profiles,
    required this.myRank,
    required this.promotionZone,
    required this.relegationZone,
  });

  /// The seat the caller holds: group, tier and week.
  final WeeklyLeagueSeat seat;

  /// The user this reading was made for.
  final UserId readerId;

  /// Every member of the group, best first, each with a distinct rank and
  /// the outcome the week would give them if it closed now.
  final List<WeeklyLeaguePlacing> placings;

  /// The name and picture version of each member, keyed by user. A member
  /// the profile reader did not know is absent here, never dropped from
  /// [placings].
  final Map<UserId, WeeklyLeagueMemberProfile> profiles;

  /// The caller's 1-based rank in [placings].
  final int myRank;

  /// How many places from the top move up: the promotion line falls after
  /// this rank. Zero in the top tier and in a group too small to move
  /// anyone.
  final int promotionZone;

  /// How many places from the bottom move down: the relegation line falls
  /// before the last this many ranks. Zero in the bottom tier and in a group
  /// too small to move anyone.
  final int relegationZone;

  /// How many members the group holds.
  int get size => placings.length;
}
