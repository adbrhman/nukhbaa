/// Use-case: count the caller's own streak.
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/football_data/provider_sync_rules.dart'
    show riyadhDayOf;
import 'package:application/src/gamification/ports/streak_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Reports how many match days in a row the caller has completed (P1-3).
///
/// Computed on every read from the completion events, never stored: see
/// [StreakTally] for why there is no streak table.
///
/// Only the caller's own streak, always: there is no surface for reading
/// someone else's, so the principal is the whole of the authority check.
///
/// Never throws; returns a typed [Result].
final class GetMyStreak {
  /// Creates the use-case over its collaborators.
  const GetMyStreak({required StreakRepository streaks, required Clock clock})
    : _streaks = streaks,
      _clock = clock;

  final StreakRepository _streaks;
  final Clock _clock;

  /// How far back the count looks. Comfortably longer than a sporting season
  /// (September through August), so a full season's run is always visible,
  /// while still bounding the query on a 0.2-vCPU container.
  static const int windowDays = 400;

  /// Counts [principal]'s run as of now.
  Future<Result<StreakTally>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final today = riyadhDayOf(_clock.nowUtc());
    final calendarResult = await _streaks.completionCalendar(
      userId: principal.userId,
      upToDay: today,
      limitDays: windowDays,
    );
    if (calendarResult is Err<List<MatchDayCompletion>>) {
      return Result.err(calendarResult.error);
    }
    final calendar = (calendarResult as Ok<List<MatchDayCompletion>>).value;
    if (calendar.isEmpty) {
      return const Result.ok(StreakTally.none);
    }

    // Today counts as a break only once it is over. The flag is set only when
    // the newest match day IS today — on a day with no fixtures the newest
    // entry is an earlier day, and an earlier incomplete day is a real miss.
    final newest = calendar.first;
    final pendingToday =
        newest.day.isAtSameMomentAs(today) && !newest.completed;

    return Result.ok(
      StreakTally.fromMatchDays(<bool>[
        for (final entry in calendar) entry.completed,
      ], newestIsPendingToday: pendingToday),
    );
  }
}
