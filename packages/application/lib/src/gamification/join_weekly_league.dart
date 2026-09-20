/// Use-case: seat the caller in this week's league (P2-3).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/weekly_league_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Places the caller in a group of the current Riyadh week, or returns the
/// seat they already hold.
///
/// **Lazy, not drawn at midnight.** There is no Monday job that seats the
/// whole platform. A player is seated the first time they are seen in the
/// week, so a player who installs the app on Wednesday plays on Wednesday
/// instead of waiting six days for a draw. The cost is that a group holds
/// only players who showed up, which is the group worth competing in.
///
/// **Idempotent.** A seat that exists is returned untouched: no second
/// placement, no write, and the `joinedAt` that breaks ties stays the
/// moment the player actually arrived.
///
/// **The tier comes from the ladder, not from form.** It is the tier the
/// player's newest judged week sent them to, and
/// [WeeklyLeagueTier.bronze] for a player no week of whose has been judged.
/// Points never decide a tier directly -- only a finished week does.
///
/// Never throws; returns a typed [Result].
final class JoinWeeklyLeague {
  /// Creates the use-case over its collaborators.
  const JoinWeeklyLeague({
    required WeeklyLeagueRepository leagues,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _leagues = leagues,
       _ids = idGenerator,
       _clock = clock;

  final WeeklyLeagueRepository _leagues;
  final IdGenerator _ids;
  final Clock _clock;

  /// Returns [principal]'s seat for the week that is open now, placing them
  /// if they hold none.
  Future<Result<WeeklyLeagueSeat>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final weekStart = WeeklyLeaguePolicy.weekStartOf(
      riyadhDayOf(_clock.nowUtc()),
    );

    final existing = await _leagues.seatFor(
      userId: principal.userId,
      weekStart: weekStart,
    );
    if (existing is Err<WeeklyLeagueSeat?>) {
      return Result.err(existing.error);
    }
    final seat = (existing as Ok<WeeklyLeagueSeat?>).value;
    if (seat != null) {
      return Result.ok(seat);
    }

    final finishResult = await _leagues.lastFinishOf(userId: principal.userId);
    if (finishResult is Err<WeeklyLeagueFinish?>) {
      return Result.err(finishResult.error);
    }
    final finish = (finishResult as Ok<WeeklyLeagueFinish?>).value;
    final tier = finish == null
        ? WeeklyLeagueTier.bronze
        : WeeklyLeaguePolicy.nextTier(finish.tier, finish.outcome);

    final idResult = WeeklyLeagueId.tryParse(_ids.newUuid());
    if (idResult is Err<WeeklyLeagueId>) {
      return Result.err(idResult.error);
    }

    return _leagues.place(
      userId: principal.userId,
      weekStart: weekStart,
      tier: tier,
      newLeagueId: (idResult as Ok<WeeklyLeagueId>).value,
      capacity: WeeklyLeaguePolicy.groupCapacity,
    );
  }
}
