/// `GET /owner/h2h-cup`: the whole Elite Cup of a month, for the owners'
/// page (script 304): the month's rounds and the three paths with their
/// qualifiers, stages, pairs, results and titles.
///
/// Names, days and the figures that decided a pair only: nobody's
/// prediction crosses this wire.
library;

import 'package:contracts/src/h2h_cup_dto.dart';

/// A month of the cup window.
final class OwnerH2hCupMonthDto {
  /// Creates the line.
  const OwnerH2hCupMonthDto({required this.monthStart, required this.hasCup});

  /// Deserializes from a JSON map, tolerating missing keys.
  factory OwnerH2hCupMonthDto.fromJson(Map<String, Object?> json) =>
      OwnerH2hCupMonthDto(
        monthStart: (json['month_start'] as String?) ?? '',
        hasCup: (json['has_cup'] as bool?) ?? false,
      );

  /// The first day of the month (`YYYY-MM-DD`).
  final String monthStart;

  /// Whether the month has qualifiers.
  final bool hasCup;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'month_start': monthStart,
    'has_cup': hasCup,
  };
}

/// A round of the month.
final class OwnerH2hCupRoundDto {
  /// Creates the line.
  const OwnerH2hCupRoundDto({
    required this.number,
    required this.day,
    required this.fixtureCount,
    required this.locked,
    required this.bySystem,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory OwnerH2hCupRoundDto.fromJson(Map<String, Object?> json) =>
      OwnerH2hCupRoundDto(
        number: (json['number'] as int?) ?? 0,
        day: (json['day'] as String?) ?? '',
        fixtureCount: (json['fixture_count'] as int?) ?? 0,
        locked: (json['locked'] as bool?) ?? false,
        bySystem: (json['by_system'] as bool?) ?? false,
      );

  /// Its number in the month.
  final int number;

  /// Its Riyadh day (`YYYY-MM-DD`).
  final String day;

  /// The fixtures it held when approved.
  final int fixtureCount;

  /// Whether its fixture list is frozen.
  final bool locked;

  /// Whether the scheduler approved it, not an admin.
  final bool bySystem;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'number': number,
    'day': day,
    'fixture_count': fixtureCount,
    'locked': locked,
    'by_system': bySystem,
  };
}

/// One path of the cup.
final class OwnerH2hCupPathDto {
  /// Creates the path.
  const OwnerH2hCupPathDto({
    required this.place,
    required this.entrants,
    required this.stages,
    this.title,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory OwnerH2hCupPathDto.fromJson(Map<String, Object?> json) =>
      OwnerH2hCupPathDto(
        place: (json['place'] as int?) ?? 0,
        entrants: [
          for (final Object? e in (json['entrants'] as List<Object?>?) ?? [])
            if (e is Map<String, Object?>) H2hCupPlayerDto.fromJson(e),
        ],
        stages: [
          for (final Object? s in (json['stages'] as List<Object?>?) ?? [])
            if (s is Map<String, Object?>) H2hCupStageDto.fromJson(s),
        ],
        title: json['title'] is Map<String, Object?>
            ? H2hCupTitleDto.fromJson(json['title']! as Map<String, Object?>)
            : null,
      );

  /// 1, 2 or 3.
  final int place;

  /// Its qualifiers, by group.
  final List<H2hCupPlayerDto> entrants;

  /// Semi-finals, then the final.
  final List<H2hCupStageDto> stages;

  /// The title once decided.
  final H2hCupTitleDto? title;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'place': place,
    'entrants': [for (final H2hCupPlayerDto e in entrants) e.toJson()],
    'stages': [for (final H2hCupStageDto s in stages) s.toJson()],
    if (title != null) 'title': title!.toJson(),
  };
}

/// `GET /owner/h2h-cup`.
final class OwnerH2hCupDto {
  /// Creates the cup.
  const OwnerH2hCupDto({
    required this.monthStart,
    required this.months,
    required this.rounds,
    required this.paths,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory OwnerH2hCupDto.fromJson(Map<String, Object?> json) => OwnerH2hCupDto(
    schemaVersion: (json['schema_version'] as int?) ?? 1,
    monthStart: (json['month_start'] as String?) ?? '',
    months: [
      for (final Object? m in (json['months'] as List<Object?>?) ?? [])
        if (m is Map<String, Object?>) OwnerH2hCupMonthDto.fromJson(m),
    ],
    rounds: [
      for (final Object? r in (json['rounds'] as List<Object?>?) ?? [])
        if (r is Map<String, Object?>) OwnerH2hCupRoundDto.fromJson(r),
    ],
    paths: [
      for (final Object? p in (json['paths'] as List<Object?>?) ?? [])
        if (p is Map<String, Object?>) OwnerH2hCupPathDto.fromJson(p),
    ],
  );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The month shown (`YYYY-MM-DD`).
  final String monthStart;

  /// The months the cup keeps.
  final List<OwnerH2hCupMonthDto> months;

  /// The month's approved rounds.
  final List<OwnerH2hCupRoundDto> rounds;

  /// The three paths; empty before the month has qualifiers.
  final List<OwnerH2hCupPathDto> paths;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'month_start': monthStart,
    'months': [for (final OwnerH2hCupMonthDto m in months) m.toJson()],
    'rounds': [for (final OwnerH2hCupRoundDto r in rounds) r.toJson()],
    'paths': [for (final OwnerH2hCupPathDto p in paths) p.toJson()],
  };
}
