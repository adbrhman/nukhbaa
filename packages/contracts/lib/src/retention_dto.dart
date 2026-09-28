/// Body of `GET /admin/retention` (migration 0069): play per week and
/// players by the week of their first active day.
library;

/// How many players a horizon could judge, and how many of them came back.
final class RetentionRateDto {
  /// Creates the rate.
  const RetentionRateDto({required this.eligible, required this.retained});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory RetentionRateDto.fromJson(Map<String, Object?> json) =>
      RetentionRateDto(
        eligible: (json['eligible'] as int?) ?? 0,
        retained: (json['retained'] as int?) ?? 0,
      );

  /// Players whose day (or week) has ended.
  final int eligible;

  /// Of them, those active on it.
  final int retained;

  /// The share, 0..100 rounded; null while nobody can be judged yet.
  int? get percent =>
      eligible == 0 ? null : (retained * 100 / eligible).round();

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'eligible': eligible, 'retained': retained};
}

/// One week of play.
final class RetentionWeekDto {
  /// Creates the week.
  const RetentionWeekDto({
    required this.weekStart,
    required this.complete,
    required this.activeUsers,
    required this.active3Plus,
    required this.leagueActive,
    required this.leagueActive3Plus,
    required this.leagueMembers,
    required this.leagueReturned,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory RetentionWeekDto.fromJson(Map<String, Object?> json) =>
      RetentionWeekDto(
        weekStart: (json['week_start'] as String?) ?? '',
        complete: (json['complete'] as bool?) ?? false,
        activeUsers: (json['active_users'] as int?) ?? 0,
        active3Plus: (json['active_3plus'] as int?) ?? 0,
        leagueActive: (json['league_active'] as int?) ?? 0,
        leagueActive3Plus: (json['league_active_3plus'] as int?) ?? 0,
        leagueMembers: (json['league_members'] as int?) ?? 0,
        leagueReturned: json['league_returned'] as int?,
      );

  /// The Monday opening the week, `YYYY-MM-DD` (Riyadh).
  final String weekStart;

  /// Whether the week has ended.
  final bool complete;

  /// Players active on at least one day.
  final int activeUsers;

  /// Of them, those active on three days or more.
  final int active3Plus;

  /// Of [activeUsers], those holding a weekly-league seat.
  final int leagueActive;

  /// Of [leagueActive], those active on three days or more.
  final int leagueActive3Plus;

  /// Weekly-league seats taken that week.
  final int leagueMembers;

  /// Of [leagueMembers], those seated again the next week; null until the
  /// next week has ended.
  final int? leagueReturned;

  /// The share active on three days or more, 0..100; null with no player.
  int? get active3PlusPercent =>
      activeUsers == 0 ? null : (active3Plus * 100 / activeUsers).round();

  /// The same share among league players; null with none.
  int? get league3PlusPercent => leagueActive == 0
      ? null
      : (leagueActive3Plus * 100 / leagueActive).round();

  /// The same share among everyone else; null with none.
  int? get others3PlusPercent {
    final int others = activeUsers - leagueActive;
    return others <= 0
        ? null
        : ((active3Plus - leagueActive3Plus) * 100 / others).round();
  }

  /// The share of seats held again the next week; null until it is known
  /// or with no seat.
  int? get leagueRetentionPercent {
    final int? returned = leagueReturned;
    return returned == null || leagueMembers == 0
        ? null
        : (returned * 100 / leagueMembers).round();
  }

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'week_start': weekStart,
    'complete': complete,
    'active_users': activeUsers,
    'active_3plus': active3Plus,
    'league_active': leagueActive,
    'league_active_3plus': leagueActive3Plus,
    'league_members': leagueMembers,
    'league_returned': leagueReturned,
  };
}

/// Players whose first active day fell in one week, and who came back.
final class RetentionCohortDto {
  /// Creates the cohort.
  const RetentionCohortDto({
    required this.weekStart,
    required this.users,
    required this.day1,
    required this.day7,
    required this.day14,
    required this.week4,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory RetentionCohortDto.fromJson(Map<String, Object?> json) =>
      RetentionCohortDto(
        weekStart: (json['week_start'] as String?) ?? '',
        users: (json['users'] as int?) ?? 0,
        day1: _rate(json['day1']),
        day7: _rate(json['day7']),
        day14: _rate(json['day14']),
        week4: _rate(json['week4']),
      );

  /// The Monday of the week, `YYYY-MM-DD` (Riyadh).
  final String weekStart;

  /// Players whose first active day fell in it.
  final int users;

  /// Active the day after their first.
  final RetentionRateDto day1;

  /// Active on the seventh day after their first.
  final RetentionRateDto day7;

  /// Active on the fourteenth day after their first.
  final RetentionRateDto day14;

  /// Active on any of days 21 to 27 after their first.
  final RetentionRateDto week4;

  static RetentionRateDto _rate(Object? raw) => RetentionRateDto.fromJson(
    ((raw as Map<Object?, Object?>?) ?? const <Object?, Object?>{})
        .cast<String, Object?>(),
  );

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'week_start': weekStart,
    'users': users,
    'day1': day1.toJson(),
    'day7': day7.toJson(),
    'day14': day14.toJson(),
    'week4': week4.toJson(),
  };
}

/// Body of `GET /admin/retention`: [weeks] and [cohorts], newest first,
/// every week of the window present.
final class AdminRetentionDto {
  /// Creates the body.
  const AdminRetentionDto({
    required this.today,
    required this.weeks,
    required this.cohorts,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory AdminRetentionDto.fromJson(Map<String, Object?> json) =>
      AdminRetentionDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        today: (json['today'] as String?) ?? '',
        weeks: [
          for (final Object? w
              in (json['weeks'] as List<Object?>?) ?? const <Object?>[])
            RetentionWeekDto.fromJson(
              (w! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
        ],
        cohorts: [
          for (final Object? c
              in (json['cohorts'] as List<Object?>?) ?? const <Object?>[])
            RetentionCohortDto.fromJson(
              (c! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The Riyadh day the figures were read on, `YYYY-MM-DD`.
  final String today;

  /// Play per week, newest first.
  final List<RetentionWeekDto> weeks;

  /// Players by the week of their first active day, newest first.
  final List<RetentionCohortDto> cohorts;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'today': today,
    'weeks': [for (final w in weeks) w.toJson()],
    'cohorts': [for (final c in cohorts) c.toJson()],
  };
}
