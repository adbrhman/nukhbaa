// NK340_01
/// One action an owner took, as the owners' own log reads it (script 340).
///
/// The line comes from one of two tables: `owner` for a request to `/owner`
/// (`admin.owner_audit_log`), `admin` for a change made inside the admins'
/// tools by an owner seat (`admin.admin_activity_log`). The two tables count
/// their ids apart, so a line is told apart by [source] and [id] together.
final class OwnerAuditEntryDto {
  /// Creates the line.
  const OwnerAuditEntryDto({
    required this.source,
    required this.id,
    required this.actorName,
    required this.method,
    required this.path,
    required this.at,
    this.target,
    this.result,
  });

  /// Deserializes from a JSON map.
  factory OwnerAuditEntryDto.fromJson(Map<String, Object?> json) =>
      OwnerAuditEntryDto(
        source: json['source']! as String,
        id: json['id']! as int,
        actorName: json['actor_name']! as String,
        method: json['method']! as String,
        path: json['path']! as String,
        at: DateTime.parse(json['at']! as String).toUtc(),
        target: json['target'] as String?,
        result: json['result'] as String?,
      );

  /// Which table the line came from: `owner` or `admin`.
  final String source;

  /// The row's id inside its own table.
  final int id;

  /// The owner who acted, by name.
  final String actorName;

  /// `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// The request's path.
  final String path;

  /// When (UTC).
  final DateTime at;

  /// The player or the match it touched, as it reads now (admin lines only).
  final String? target;

  /// That match's result as it stands now (admin lines only).
  final String? result;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'source': source,
    'id': id,
    'actor_name': actorName,
    'method': method,
    'path': path,
    'at': at.toUtc().toIso8601String(),
    'target': target,
    'result': result,
  };

  @override
  bool operator ==(Object other) =>
      other is OwnerAuditEntryDto &&
      other.source == source &&
      other.id == id &&
      other.actorName == actorName &&
      other.method == method &&
      other.path == path &&
      other.at == at &&
      other.target == target &&
      other.result == result;

  @override
  int get hashCode =>
      Object.hash(source, id, actorName, method, path, at, target, result);
}

/// The wire shape of `GET /owner/audit` (script 340).
final class OwnerAuditLogDto {
  /// Creates the DTO.
  const OwnerAuditLogDto({
    required this.entries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory OwnerAuditLogDto.fromJson(Map<String, Object?> json) =>
      OwnerAuditLogDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        entries: [
          for (final line in json['entries']! as List<Object?>)
            OwnerAuditEntryDto.fromJson(line! as Map<String, Object?>),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owners' latest actions, the newest first.
  final List<OwnerAuditEntryDto> entries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'entries': [for (final line in entries) line.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! OwnerAuditLogDto ||
        other.schemaVersion != schemaVersion ||
        other.entries.length != entries.length) {
      return false;
    }
    for (var i = 0; i < entries.length; i++) {
      if (other.entries[i] != entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(entries));
}
