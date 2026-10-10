/// Wire shapes of the admin's controls over the head-to-head league
/// (migration 0101): the settings, the days kept from automatic approval,
/// the admin log, late seats, the month report and a manual run of the
/// league's jobs.
///
/// Every number is server-produced (Axioms 2/5): the client shows what the
/// server sent and sends back only the admin's choices. Days cross the wire
/// as plain `YYYY-MM-DD` Riyadh dates; instants as ISO-8601 UTC.
library;

List<Map<String, Object?>> _maps(Object? raw) => [
  for (final e in (raw as List<Object?>?) ?? const <Object?>[])
    (e! as Map<Object?, Object?>).cast<String, Object?>(),
];

Map<String, int> _counts(Object? raw) => <String, int>{
  for (final e
      in ((raw as Map<Object?, Object?>?) ?? const <Object?, Object?>{})
          .entries)
    if (e.value is int) e.key.toString(): e.value! as int,
};

/// The league's settings, with the bounds the server accepts.
final class H2hSettingsDto {
  /// Creates the settings.
  const H2hSettingsDto({
    required this.autoApprove,
    required this.leadHours,
    required this.minActiveDays,
    this.leadHoursMin = 1,
    this.leadHoursMax = 24,
    this.minActiveDaysMin = 1,
    this.minActiveDaysMax = 28,
    this.updatedByName,
    this.updatedAt,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hSettingsDto.fromJson(Map<String, Object?> json) => H2hSettingsDto(
    autoApprove: (json['auto_approve'] as bool?) ?? true,
    leadHours: (json['lead_hours'] as int?) ?? 24,
    minActiveDays: (json['min_active_days'] as int?) ?? 5,
    leadHoursMin: (json['lead_hours_min'] as int?) ?? 1,
    leadHoursMax: (json['lead_hours_max'] as int?) ?? 24,
    minActiveDaysMin: (json['min_active_days_min'] as int?) ?? 1,
    minActiveDaysMax: (json['min_active_days_max'] as int?) ?? 28,
    updatedByName: json['updated_by_name'] as String?,
    updatedAt: json['updated_at'] as String?,
  );

  /// Whether the server approves regular days by itself.
  final bool autoApprove;

  /// How many hours before a day's first kickoff it may approve the day.
  final int leadHours;

  /// Days of predictions in a month that keep a player in the next draw.
  final int minActiveDays;

  /// The fewest hours [leadHours] may be.
  final int leadHoursMin;

  /// The most hours [leadHours] may be.
  final int leadHoursMax;

  /// The fewest days [minActiveDays] may be.
  final int minActiveDaysMin;

  /// The most days [minActiveDays] may be.
  final int minActiveDaysMax;

  /// Who changed them last, or null while the defaults stand.
  final String? updatedByName;

  /// When they were changed last, ISO-8601 UTC, or null.
  final String? updatedAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'auto_approve': autoApprove,
    'lead_hours': leadHours,
    'min_active_days': minActiveDays,
    'lead_hours_min': leadHoursMin,
    'lead_hours_max': leadHoursMax,
    'min_active_days_min': minActiveDaysMin,
    'min_active_days_max': minActiveDaysMax,
    'updated_by_name': updatedByName,
    'updated_at': updatedAt,
  };
}

/// Request body of `PUT /admin/h2h/settings`.
final class H2hSettingsRequestDto {
  /// Creates a request.
  const H2hSettingsRequestDto({
    required this.autoApprove,
    required this.leadHours,
    required this.minActiveDays,
  });

  /// The admin's choice for [H2hSettingsDto.autoApprove].
  final bool autoApprove;

  /// The admin's choice for [H2hSettingsDto.leadHours].
  final int leadHours;

  /// The admin's choice for [H2hSettingsDto.minActiveDays].
  final int minActiveDays;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'auto_approve': autoApprove,
    'lead_hours': leadHours,
    'min_active_days': minActiveDays,
  };
}

/// One day of the month in the controls.
final class H2hControlDayDto {
  /// Creates a day.
  const H2hControlDayDto({
    required this.day,
    required this.fixtureCount,
    required this.excluded,
    this.firstKickoff,
    this.round,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hControlDayDto.fromJson(Map<String, Object?> json) =>
      H2hControlDayDto(
        day: (json['day'] as String?) ?? '',
        fixtureCount: (json['fixture_count'] as int?) ?? 0,
        excluded: (json['excluded'] as bool?) ?? false,
        firstKickoff: json['first_kickoff'] as String?,
        round: json['round'] as int?,
      );

  /// The Riyadh day, `YYYY-MM-DD`.
  final String day;

  /// Fixtures of the day.
  final int fixtureCount;

  /// Whether the server must not approve it by itself.
  final bool excluded;

  /// The first kickoff, ISO-8601 UTC, when known.
  final String? firstKickoff;

  /// The round the day already is, or null.
  final int? round;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'day': day,
    'fixture_count': fixtureCount,
    'excluded': excluded,
    'first_kickoff': firstKickoff,
    'round': round,
  };
}

/// One line of the admin log.
final class H2hAdminActionDto {
  /// Creates a line.
  const H2hAdminActionDto({
    required this.id,
    required this.action,
    required this.detail,
    required this.actedAt,
    this.actorId,
    this.actorName,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAdminActionDto.fromJson(Map<String, Object?> json) =>
      H2hAdminActionDto(
        id: (json['id'] as String?) ?? '',
        action: (json['action'] as String?) ?? '',
        detail:
            ((json['detail'] as Map<Object?, Object?>?) ??
                    const <Object?, Object?>{})
                .cast<String, Object?>(),
        actedAt: (json['acted_at'] as String?) ?? '',
        actorId: json['actor_id'] as String?,
        actorName: json['actor_name'] as String?,
      );

  /// The line (UUID string).
  final String id;

  /// `settings_saved`, `day_excluded`, `day_included`, `round_approved`,
  /// `round_withdrawn`, `seat_added`, `jobs_run` or `pilot_started`.
  final String action;

  /// What it was done to, as the server logged it.
  final Map<String, Object?> detail;

  /// When, ISO-8601 UTC.
  final String actedAt;

  /// Who (UUID string), or null for the system.
  final String? actorId;

  /// Their display name, or null for the system.
  final String? actorName;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'id': id,
    'action': action,
    'detail': detail,
    'acted_at': actedAt,
    'actor_id': actorId,
    'actor_name': actorName,
  };
}

/// Response body of `GET /admin/h2h/controls`.
final class H2hControlsDto {
  /// Creates the reading.
  const H2hControlsDto({
    required this.monthStart,
    required this.settings,
    required this.days,
    required this.actions,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory H2hControlsDto.fromJson(Map<String, Object?> json) => H2hControlsDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    monthStart: (json['month_start'] as String?) ?? '',
    settings: H2hSettingsDto.fromJson(
      ((json['settings'] as Map<Object?, Object?>?) ??
              const <Object?, Object?>{})
          .cast<String, Object?>(),
    ),
    days: [for (final m in _maps(json['days'])) H2hControlDayDto.fromJson(m)],
    actions: [
      for (final m in _maps(json['actions'])) H2hAdminActionDto.fromJson(m),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The month, `YYYY-MM-DD` of its first day.
  final String monthStart;

  /// The settings as they stand.
  final H2hSettingsDto settings;

  /// The month's days from today on: not started, or excluded.
  final List<H2hControlDayDto> days;

  /// The latest lines of the admin log, newest first.
  final List<H2hAdminActionDto> actions;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'month_start': monthStart,
    'settings': settings.toJson(),
    'days': [for (final d in days) d.toJson()],
    'actions': [for (final a in actions) a.toJson()],
  };
}

/// Request body of `POST /admin/h2h/exclusions`.
final class H2hDayExclusionRequestDto {
  /// Creates a request.
  const H2hDayExclusionRequestDto({required this.day, required this.excluded});

  /// The Riyadh day, `YYYY-MM-DD`.
  final String day;

  /// True keeps it from automatic approval; false lifts that.
  final bool excluded;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'day': day, 'excluded': excluded};
}

/// Request body of `POST /admin/h2h/seats`.
final class H2hSeatRequestDto {
  /// Creates a request.
  const H2hSeatRequestDto({
    required this.leagueId,
    required this.userId,
    required this.slot,
    this.day,
  });

  /// The group (UUID string).
  final String leagueId;

  /// The player (UUID string).
  final String userId;

  /// The empty seat of the group, 0-based.
  final int slot;

  /// A day of the month (`YYYY-MM-DD`); today's month when null.
  final String? day;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'league_id': leagueId,
    'user_id': userId,
    'slot': slot,
    if (day != null) 'day': day,
  };
}

/// Response body of `GET /admin/h2h/report`.
final class H2hMonthReportDto {
  /// Creates a report.
  const H2hMonthReportDto({
    required this.monthStart,
    required this.drawn,
    required this.isPilot,
    required this.drawnSeats,
    required this.seats,
    required this.groupsByDivision,
    required this.closed,
    required this.closedMembers,
    required this.outcomes,
    this.drawnAt,
    this.closedAt,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hMonthReportDto.fromJson(Map<String, Object?> json) =>
      H2hMonthReportDto(
        monthStart: (json['month_start'] as String?) ?? '',
        drawn: (json['drawn'] as bool?) ?? false,
        isPilot: (json['is_pilot'] as bool?) ?? false,
        drawnSeats: (json['drawn_seats'] as int?) ?? 0,
        seats: (json['seats'] as int?) ?? 0,
        groupsByDivision: _counts(json['groups_by_division']),
        closed: (json['closed'] as bool?) ?? false,
        closedMembers: (json['closed_members'] as int?) ?? 0,
        outcomes: _counts(json['outcomes']),
        drawnAt: json['drawn_at'] as String?,
        closedAt: json['closed_at'] as String?,
      );

  /// The month, `YYYY-MM-DD` of its first day.
  final String monthStart;

  /// Whether the month was drawn.
  final bool drawn;

  /// Whether it is the pilot month.
  final bool isPilot;

  /// Players the draw seated.
  final int drawnSeats;

  /// Seats held now: the draw's and any added late.
  final int seats;

  /// Groups per division level (`"1"` .. `"4"`).
  final Map<String, int> groupsByDivision;

  /// Whether the month was judged.
  final bool closed;

  /// Members it judged.
  final int closedMembers;

  /// Members per outcome (`promoted`, `held`, `relegated`, `out`, ...).
  final Map<String, int> outcomes;

  /// When it was drawn, ISO-8601 UTC, or null.
  final String? drawnAt;

  /// When it was judged, ISO-8601 UTC, or null.
  final String? closedAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'month_start': monthStart,
    'drawn': drawn,
    'is_pilot': isPilot,
    'drawn_seats': drawnSeats,
    'seats': seats,
    'groups_by_division': groupsByDivision,
    'closed': closed,
    'closed_members': closedMembers,
    'outcomes': outcomes,
    'drawn_at': drawnAt,
    'closed_at': closedAt,
  };
}

/// Response body of `POST /admin/h2h/jobs`.
final class H2hJobsRunDto {
  /// Creates a report.
  const H2hJobsRunDto({
    required this.approved,
    required this.locked,
    required this.closedMonths,
    required this.drawnSeats,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hJobsRunDto.fromJson(Map<String, Object?> json) => H2hJobsRunDto(
    approved: (json['approved'] as int?) ?? 0,
    locked: (json['locked'] as int?) ?? 0,
    closedMonths: (json['closed_months'] as int?) ?? 0,
    drawnSeats: (json['drawn_seats'] as int?) ?? 0,
  );

  /// Rounds the server approved.
  final int approved;

  /// Rounds whose fixture list was frozen.
  final int locked;

  /// Months judged.
  final int closedMonths;

  /// Seats handed out by a draw.
  final int drawnSeats;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'approved': approved,
    'locked': locked,
    'closed_months': closedMonths,
    'drawn_seats': drawnSeats,
  };
}
