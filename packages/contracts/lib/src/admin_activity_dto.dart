// NK300_07
/// One change an admin made, as the owners read it (script 300).
final class AdminActivityDto {
  /// Creates the line.
  const AdminActivityDto({
    required this.id,
    required this.actorName,
    required this.method,
    required this.path,
    required this.at,
    this.target,
    this.result,
  });

  /// Deserializes from a JSON map.
  factory AdminActivityDto.fromJson(Map<String, Object?> json) =>
      AdminActivityDto(
        id: json['id']! as int,
        actorName: json['actor_name']! as String,
        method: json['method']! as String,
        path: json['path']! as String,
        at: DateTime.parse(json['at']! as String).toUtc(),
        target: json['target'] as String?,
        result: json['result'] as String?,
      );

  /// The row's id.
  final int id;

  /// The admin who made it, by name.
  final String actorName;

  /// `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// The request's path.
  final String path;

  /// When (UTC).
  final DateTime at;

  /// The player or the match it touched, as it reads now.
  final String? target;

  /// That match's result as it stands now.
  final String? result;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'id': id,
    'actor_name': actorName,
    'method': method,
    'path': path,
    'at': at.toUtc().toIso8601String(),
    'target': target,
    'result': result,
  };
}

/// The wire shape of `GET /owner/admin-activity` (script 300).
final class AdminActivityLogDto {
  /// Creates the DTO.
  const AdminActivityLogDto({
    required this.entries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory AdminActivityLogDto.fromJson(Map<String, Object?> json) =>
      AdminActivityLogDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        entries: [
          for (final line in json['entries']! as List<Object?>)
            AdminActivityDto.fromJson(line! as Map<String, Object?>),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The latest changes, the newest first.
  final List<AdminActivityDto> entries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'entries': [for (final line in entries) line.toJson()],
  };
}
