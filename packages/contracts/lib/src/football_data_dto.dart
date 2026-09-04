/// Versioned wire shape for the Football Data team catalog (`GET /teams`).
///
/// Pure data shape shared verbatim by client and server; depends on nothing
/// (Application ADR §3).
library;

/// A single team's identity as it crosses the wire: id, display name, an
/// optional short code, and an optional crest URL.
final class TeamDto {
  /// Creates a team DTO.
  const TeamDto({
    required this.id,
    required this.name,
    required this.shortName,
    required this.crestUrl,
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

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'name': name,
    'short_name': shortName,
    'crest_url': crestUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is TeamDto &&
      other.id == id &&
      other.name == name &&
      other.shortName == shortName &&
      other.crestUrl == crestUrl &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(id, name, shortName, crestUrl, schemaVersion);
}
