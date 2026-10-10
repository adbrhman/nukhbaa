/// Wire shapes the admin reads the head-to-head league with (migration
/// 0100): every group of a month with its table (`GET /admin/h2h/groups`).
/// Every number is server-produced (Axioms 2/5); no prediction of anybody
/// crosses this wire.
library;

import 'package:contracts/src/h2h_league_dto.dart';

List<Map<String, Object?>> _maps(Object? raw) => [
  for (final e in (raw as List<Object?>?) ?? const <Object?>[])
    (e! as Map<Object?, Object?>).cast<String, Object?>(),
];

/// One group of the month.
final class H2hAdminGroupDto {
  /// Creates a group.
  const H2hAdminGroupDto({
    required this.leagueId,
    required this.division,
    required this.groupIndex,
    required this.capacity,
    required this.promotionZone,
    required this.relegationZone,
    required this.standings,
    this.freeSlots = const <int>[],
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory H2hAdminGroupDto.fromJson(Map<String, Object?> json) =>
      H2hAdminGroupDto(
        leagueId: (json['league_id'] as String?) ?? '',
        division: (json['division'] as int?) ?? 4,
        groupIndex: (json['group_index'] as int?) ?? 0,
        capacity: (json['capacity'] as int?) ?? 0,
        promotionZone: (json['promotion_zone'] as int?) ?? 0,
        relegationZone: (json['relegation_zone'] as int?) ?? 0,
        standings: [
          for (final m in _maps(json['standings'])) H2hStandingDto.fromJson(m),
        ],
        freeSlots: <int>[
          for (final s
              in (json['free_slots'] as List<Object?>?) ?? const <Object?>[])
            if (s is int) s,
        ],
      );

  /// The group (UUID string).
  final String leagueId;

  /// Its division, 1..4.
  final int division;

  /// 0-based index among the groups of its division.
  final int groupIndex;

  /// Seats of its round-robin.
  final int capacity;

  /// Places from the top that go up if the month ended now.
  final int promotionZone;

  /// Places from the bottom that go down if the month ended now.
  final int relegationZone;

  /// The table over the settled rounds, best first.
  final List<H2hStandingDto> standings;

  /// The seats of the round-robin no member holds, 0-based: where a
  /// late player may be seated. Empty from servers before batch 92.
  final List<int> freeSlots;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'league_id': leagueId,
    'division': division,
    'group_index': groupIndex,
    'capacity': capacity,
    'promotion_zone': promotionZone,
    'relegation_zone': relegationZone,
    'standings': [for (final s in standings) s.toJson()],
    'free_slots': freeSlots,
  };
}

/// Response body of `GET /admin/h2h/groups`.
final class H2hAdminGroupsDto {
  /// Creates the reading.
  const H2hAdminGroupsDto({
    required this.monthStart,
    required this.drawn,
    required this.isPilot,
    required this.seatedCount,
    required this.rounds,
    required this.groups,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory H2hAdminGroupsDto.fromJson(Map<String, Object?> json) =>
      H2hAdminGroupsDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        monthStart: (json['month_start'] as String?) ?? '',
        drawn: (json['drawn'] as bool?) ?? false,
        isPilot: (json['is_pilot'] as bool?) ?? false,
        seatedCount: (json['seated_count'] as int?) ?? 0,
        rounds: [
          for (final m in _maps(json['rounds'])) H2hRoundDto.fromJson(m),
        ],
        groups: [
          for (final m in _maps(json['groups'])) H2hAdminGroupDto.fromJson(m),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The month's first day, `YYYY-MM-DD`.
  final String monthStart;

  /// Whether the month was drawn.
  final bool drawn;

  /// Whether it is the pilot month.
  final bool isPilot;

  /// Players seated by the draw.
  final int seatedCount;

  /// The approved rounds, in order.
  final List<H2hRoundDto> rounds;

  /// The groups, by division then index.
  final List<H2hAdminGroupDto> groups;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'month_start': monthStart,
    'drawn': drawn,
    'is_pilot': isPilot,
    'seated_count': seatedCount,
    'rounds': [for (final r in rounds) r.toJson()],
    'groups': [for (final g in groups) g.toJson()],
  };
}
