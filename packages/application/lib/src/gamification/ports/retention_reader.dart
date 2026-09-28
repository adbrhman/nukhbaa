import 'package:shared/shared.dart';

/// One Riyadh week of play, as the measurement views of migration 0069 count
/// it (`kpi_weekly_engagement`, `kpi_league_retention`).
///
/// "Active" is at least one gamification event on a Riyadh day, as in 0054's
/// `daily_active_users`.
final class WeeklyActivity {
  /// Creates the week.
  const WeeklyActivity({
    required this.weekStart,
    required this.activeUsers,
    required this.active3Plus,
    required this.leagueActive,
    required this.leagueActive3Plus,
    required this.leagueMembers,
    required this.leagueReturned,
  });

  /// The Monday opening the week: a Riyadh date as a UTC midnight.
  final DateTime weekStart;

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

  /// Of [leagueMembers], those holding a seat the next week so far.
  final int leagueReturned;
}

/// Players whose first active day fell in one Riyadh week, and how many of
/// them came back.
///
/// Each horizon counts only the players it has had time to judge: a player
/// is eligible for day N once day N after their first has ended, so a young
/// cohort never reads as a poor one.
final class RetentionCohort {
  /// Creates the cohort.
  const RetentionCohort({
    required this.weekStart,
    required this.users,
    required this.day1Eligible,
    required this.day1,
    required this.day7Eligible,
    required this.day7,
    required this.day14Eligible,
    required this.day14,
    required this.week4Eligible,
    required this.week4,
  });

  /// The Monday of the week the cohort's first active days fell in.
  final DateTime weekStart;

  /// Players whose first active day fell in that week.
  final int users;

  /// Players whose day after the first has ended.
  final int day1Eligible;

  /// Of [day1Eligible], those active on that day.
  final int day1;

  /// Players whose seventh day after the first has ended.
  final int day7Eligible;

  /// Of [day7Eligible], those active on that day.
  final int day7;

  /// Players whose fourteenth day after the first has ended (0069's d14).
  final int day14Eligible;

  /// Of [day14Eligible], those active on that day.
  final int day14;

  /// Players whose fourth week (days 21 to 27) has ended (0069's w4).
  final int week4Eligible;

  /// Of [week4Eligible], those active on any day of it.
  final int week4;
}

/// Read port over the measurement views of migration 0069.
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to `ErrorKind.transient`.
abstract interface class RetentionReader {
  /// One row per week opening between [from] and [through] (Mondays, both
  /// inclusive) that saw any play or any league seat, newest first.
  Future<Result<List<WeeklyActivity>>> weeks({
    required DateTime from,
    required DateTime through,
  });

  /// One row per week whose players had their first active day between
  /// [from] and [today] (Riyadh days), newest first; [today] is the day in
  /// progress, which no horizon counts yet.
  Future<Result<List<RetentionCohort>>> cohorts({
    required DateTime from,
    required DateTime today,
  });
}
