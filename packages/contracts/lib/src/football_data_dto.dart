/// Versioned wire shape for the Football Data team catalog (`GET /teams`).
///
/// Pure data shape shared verbatim by client and server; depends on nothing
/// (Application ADR §3).
library;

/// A single team's identity as it crosses the wire: id, display name, an
/// optional short code, and an optional crest URL.
/// The wire shape of a Football Data league (`GET /leagues`), the sibling of
/// [TeamDto]. Carries display identity only -- id, name, short code, logo.
final class LeagueDto {
  /// Creates a league DTO.
  const LeagueDto({
    required this.id,
    required this.name,
    required this.shortName,
    required this.logoUrl,
    this.isContinental = false,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory LeagueDto.fromJson(Map<String, Object?> json) {
    return LeagueDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      name: json['name']! as String,
      shortName: json['short_name'] as String?,
      logoUrl: json['logo_url'] as String?,
      isContinental: (json['is_continental'] as bool?) ?? false,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The league's id (UUID string).
  final String id;

  /// The league's display name.
  final String name;

  /// A short code (e.g. "PL"), or null when none is on file.
  final String? shortName;

  /// The league's logo URL, or null when none is on file.
  final String? logoUrl;

  /// Whether this competition draws its entrants from other leagues (the
  /// Champions League, a domestic cup). Optional on the wire so an older
  /// server keeps working; absent means a plain domestic league.
  final bool isContinental;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'name': name,
    'short_name': shortName,
    'logo_url': logoUrl,
    'is_continental': isContinental,
  };

  @override
  bool operator ==(Object other) =>
      other is LeagueDto &&
      other.id == id &&
      other.name == name &&
      other.shortName == shortName &&
      other.logoUrl == logoUrl &&
      other.isContinental == isContinental &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(id, name, shortName, logoUrl, isContinental, schemaVersion);
}

final class TeamDto {
  /// Creates a team DTO.
  const TeamDto({
    required this.id,
    required this.name,
    required this.shortName,
    required this.crestUrl,
    this.leagueId,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory TeamDto.fromJson(Map<String, Object?> json) {
    return TeamDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      name: json['name']! as String,
      shortName: json['short_name'] as String?,
      crestUrl: json['crest_url'] as String?,
      leagueId: json['league_id'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The team's id (UUID string).
  final String id;

  /// The team's display name.
  final String name;

  /// A short code/abbreviation, or `null` when none is on file.
  final String? shortName;

  /// The team's crest image URL, or `null` when none is on file yet.
  final String? crestUrl;

  /// The league this team plays in, or `null` when it belongs to none.
  /// Present so a client can offer only the chosen league's clubs.
  final String? leagueId;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'name': name,
    'short_name': shortName,
    'crest_url': crestUrl,
    'league_id': leagueId,
  };

  @override
  bool operator ==(Object other) =>
      other is TeamDto &&
      other.id == id &&
      other.name == name &&
      other.shortName == shortName &&
      other.crestUrl == crestUrl &&
      other.leagueId == leagueId &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(id, name, shortName, crestUrl, leagueId, schemaVersion);
}
