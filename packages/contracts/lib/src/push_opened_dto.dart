/// Body of the answer to `POST /me/push-opened` (plan P3-8).
final class PushOpenedAckDto {
  /// Creates the answer.
  const PushOpenedAckDto({
    required this.recorded,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory PushOpenedAckDto.fromJson(Map<String, Object?> json) =>
      PushOpenedAckDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        recorded: (json['recorded'] as bool?) ?? false,
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Whether the tap was recorded.
  final bool recorded;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'recorded': recorded,
  };
}
