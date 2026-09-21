/// Body of `GET /me/notification-preferences` and of both directions of
/// `PUT /me/notification-preferences` (P3-1).
///
/// A missing switch reads as ON, the server's default: an older client that
/// never sends a newer switch cannot turn it off by omission, and a newer
/// client reading an older server sees what that server actually does.
final class NotificationPreferencesDto {
  /// Creates the switches.
  const NotificationPreferencesDto({
    required this.predictionReminder,
    this.preMatch = true,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory NotificationPreferencesDto.fromJson(Map<String, Object?> json) {
    return NotificationPreferencesDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      predictionReminder: (json['prediction_reminder'] as bool?) ?? true,
      preMatch: (json['pre_match'] as bool?) ?? true,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Whether the daily prediction reminder may reach the caller.
  final bool predictionReminder;

  /// Whether the pre-match push (plan P3-4a) may reach the caller.
  final bool preMatch;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'prediction_reminder': predictionReminder,
    'pre_match': preMatch,
  };

  @override
  bool operator ==(Object other) =>
      other is NotificationPreferencesDto &&
      other.schemaVersion == schemaVersion &&
      other.predictionReminder == predictionReminder &&
      other.preMatch == preMatch;

  @override
  int get hashCode => Object.hash(schemaVersion, predictionReminder, preMatch);
}
