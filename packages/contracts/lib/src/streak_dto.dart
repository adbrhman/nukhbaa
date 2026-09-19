/// Response body of `GET /me/streak`.
///
/// Counts only, no calendar: the client draws a number, and shipping the
/// whole day-by-day history would hand every device a payload it does not
/// render.
final class MyStreakDto {
  /// Creates the streak reading.
  const MyStreakDto({
    required this.current,
    required this.longest,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory MyStreakDto.fromJson(Map<String, Object?> json) {
    return MyStreakDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      current: (json['current'] as int?) ?? 0,
      longest: (json['longest'] as int?) ?? 0,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Completed match days in a row, counting back from the most recent one.
  final int current;

  /// The longest such run on record.
  final int longest;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'current': current,
    'longest': longest,
  };

  @override
  bool operator ==(Object other) =>
      other is MyStreakDto &&
      other.current == current &&
      other.longest == longest &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(current, longest, schemaVersion);
}
