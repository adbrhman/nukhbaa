/// Use-case: the admin's view of retention (migration 0069, plan P2-8 and
/// P4-6).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/gamification/ports/retention_reader.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One week on the retention card, every week of the window present.
final class RetentionWeek {
  /// Creates the week.
  const RetentionWeek({
    required this.weekStart,
    required this.complete,
    required this.activeUsers,
    required this.active3Plus,
    required this.leagueActive,
    required this.leagueActive3Plus,
    required this.leagueMembers,
    required this.leagueReturned,
  });

  /// The Monday opening the week (a Riyadh date as a UTC midnight).
  final DateTime weekStart;

  /// Whether the week has ended; the week in progress is still counting.
  final bool complete;

  /// Players active on at least one day of the week.
  final int activeUsers;

  /// Of them, those active on three days or more.
  final int active3Plus;

  /// Of [activeUsers], those holding a weekly-league seat that week.
  final int leagueActive;

  /// Of [leagueActive], those active on three days or more.
  final int leagueActive3Plus;

  /// Weekly-league seats taken that week.
  final int leagueMembers;

  /// Of [leagueMembers], those seated again the next week; null until the
  /// next week has ended, since a seat is taken the first time a player is
  /// seen in the week and a half-counted week would read as a drop.
  final int? leagueReturned;
}

/// The retention card: [weeks] and [cohorts], newest first, one entry for
/// every week of the window even when nobody played in it.
final class RetentionStats {
  /// Creates the stats.
  const RetentionStats({
    required this.today,
    required this.weeks,
    required this.cohorts,
  });

  /// The Riyadh day the figures were read on (a UTC midnight).
  final DateTime today;

  /// Play per week.
  final List<RetentionWeek> weeks;

  /// Players by the week of their first active day, and who came back.
  final List<RetentionCohort> cohorts;
}

/// Reads the retention figures for the admin dashboard. Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminGetRetention {
  /// Creates the use-case over its collaborators.
  const AdminGetRetention({
    required RetentionReader reader,
    required Clock clock,
  }) : _reader = reader,
       _clock = clock;

  final RetentionReader _reader;
  final Clock _clock;

  /// The window when none (or a nonsense one) is asked for.
  static const int defaultWeeks = 8;

  /// The longest window a read may cover.
  static const int maxWeeks = 26;

  /// Reads the last [weeks] weeks, the one in progress included (clamped
  /// to 1..[maxWeeks]).
  Future<Result<RetentionStats>> call({
    required AuthenticatedUser principal,
    int? weeks,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }
    final int count = weeks == null || weeks < 1
        ? defaultWeeks
        : (weeks > maxWeeks ? maxWeeks : weeks);
    final DateTime today = PredictionInsights.riyadhDayOf(_clock.nowUtc());
    final DateTime current = WeeklyLeaguePolicy.weekStartOf(today);
    final List<DateTime> mondays = <DateTime>[
      for (int i = 0; i < count; i++) current.subtract(Duration(days: 7 * i)),
    ];
    final DateTime from = mondays.last;

    final weekResult = await _reader.weeks(from: from, through: current);
    if (weekResult is Err<List<WeeklyActivity>>) {
      return Result.err(weekResult.error);
    }
    final cohortResult = await _reader.cohorts(from: from, today: today);
    if (cohortResult is Err<List<RetentionCohort>>) {
      return Result.err(cohortResult.error);
    }
    final Map<DateTime, WeeklyActivity> activity = <DateTime, WeeklyActivity>{
      for (final WeeklyActivity w
          in (weekResult as Ok<List<WeeklyActivity>>).value)
        _day(w.weekStart): w,
    };
    final Map<DateTime, RetentionCohort> cohorts = <DateTime, RetentionCohort>{
      for (final RetentionCohort c
          in (cohortResult as Ok<List<RetentionCohort>>).value)
        _day(c.weekStart): c,
    };

    return Result.ok(
      RetentionStats(
        today: today,
        weeks: <RetentionWeek>[
          for (final DateTime monday in mondays)
            _week(monday, activity[monday], today),
        ],
        cohorts: <RetentionCohort>[
          for (final DateTime monday in mondays)
            cohorts[monday] ?? _emptyCohort(monday),
        ],
      ),
    );
  }

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static RetentionWeek _week(
    DateTime monday,
    WeeklyActivity? row,
    DateTime today,
  ) {
    final bool nextWeekEnded = !today.isBefore(
      monday.add(const Duration(days: 14)),
    );
    return RetentionWeek(
      weekStart: monday,
      complete: !today.isBefore(monday.add(const Duration(days: 7))),
      activeUsers: row?.activeUsers ?? 0,
      active3Plus: row?.active3Plus ?? 0,
      leagueActive: row?.leagueActive ?? 0,
      leagueActive3Plus: row?.leagueActive3Plus ?? 0,
      leagueMembers: row?.leagueMembers ?? 0,
      leagueReturned: nextWeekEnded ? (row?.leagueReturned ?? 0) : null,
    );
  }

  static RetentionCohort _emptyCohort(DateTime monday) => RetentionCohort(
    weekStart: monday,
    users: 0,
    day1Eligible: 0,
    day1: 0,
    day7Eligible: 0,
    day7: 0,
    day14Eligible: 0,
    day14: 0,
    week4Eligible: 0,
    week4: 0,
  );
}
