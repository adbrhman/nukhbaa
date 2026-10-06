/// Body of `POST /me/screen-views` (migration 0093): how many times each
/// screen was opened since the app's last report.
final class ScreenViewsReportDto {
  /// Creates the report.
  const ScreenViewsReportDto({
    required this.opens,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys; a count that is
  /// not an integer is left out.
  factory ScreenViewsReportDto.fromJson(Map<String, Object?> json) {
    final Object? raw = json['opens'];
    return ScreenViewsReportDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      opens: <String, int>{
        if (raw is Map<String, Object?>)
          for (final MapEntry<String, Object?> e in raw.entries)
            if (e.value is int) e.key: e.value as int,
      },
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Screen name to how many times it was opened.
  final Map<String, int> opens;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'opens': opens,
  };
}

/// Body of the answer to `POST /me/screen-views`.
final class ScreenViewsAckDto {
  /// Creates the answer.
  const ScreenViewsAckDto({
    required this.recorded,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory ScreenViewsAckDto.fromJson(Map<String, Object?> json) =>
      ScreenViewsAckDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        recorded: (json['recorded'] as int?) ?? 0,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// How many of the reported screens were kept (a name the server does
  /// not know is dropped).
  final int recorded;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'recorded': recorded,
  };
}
