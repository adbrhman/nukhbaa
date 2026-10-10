/// Wire shapes of the groups an admin adds to a head-to-head month already
/// drawn (`POST /admin/h2h/extra-groups`, decided 2026-10-11).
///
/// The admin sends only how many groups; who sits where is the server's.
library;

/// Request body of `POST /admin/h2h/extra-groups`.
final class H2hAddGroupsRequestDto {
  /// Creates a request.
  const H2hAddGroupsRequestDto({required this.groups});

  /// How many groups to open, 1..10.
  final int groups;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {'groups': groups};
}

/// One group the request opened.
final class H2hAddedGroupDto {
  /// Creates a group.
  const H2hAddedGroupDto({
    required this.leagueId,
    required this.division,
    required this.groupIndex,
    required this.seats,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAddedGroupDto.fromJson(Map<String, Object?> json) =>
      H2hAddedGroupDto(
        leagueId: (json['league_id'] as String?) ?? '',
        division: (json['division'] as int?) ?? 0,
        groupIndex: (json['group_index'] as int?) ?? 0,
        seats: (json['seats'] as int?) ?? 0,
      );

  /// The group (UUID string).
  final String leagueId;

  /// Its division, 1 the top.
  final int division;

  /// 0-based position among the groups of its division.
  final int groupIndex;

  /// Players seated in it.
  final int seats;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'league_id': leagueId,
    'division': division,
    'group_index': groupIndex,
    'seats': seats,
  };
}

/// Response body of `POST /admin/h2h/extra-groups`.
final class H2hGroupsAddedDto {
  /// Creates a response.
  const H2hGroupsAddedDto({
    required this.monthStart,
    required this.groups,
    required this.seats,
    required this.waiting,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hGroupsAddedDto.fromJson(Map<String, Object?> json) =>
      H2hGroupsAddedDto(
        monthStart: (json['month_start'] as String?) ?? '',
        groups: [
          for (final e in (json['groups'] as List<Object?>?) ?? const [])
            if (e is Map<Object?, Object?>)
              H2hAddedGroupDto.fromJson(e.cast<String, Object?>()),
        ],
        seats: (json['seats'] as int?) ?? 0,
        waiting: (json['waiting'] as int?) ?? 0,
      );

  /// The month (`YYYY-MM-DD`, its first day).
  final String monthStart;

  /// The groups opened, in order.
  final List<H2hAddedGroupDto> groups;

  /// Seats handed out.
  final int seats;

  /// Qualified players still without a seat.
  final int waiting;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'month_start': monthStart,
    'groups': [for (final g in groups) g.toJson()],
    'seats': seats,
    'waiting': waiting,
  };
}
