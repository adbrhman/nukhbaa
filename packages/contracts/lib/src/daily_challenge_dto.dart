/// Response body of `GET /me/daily-challenge`.
///
/// Counts and a flag, no fixture list: the client already fetches the day's
/// fixtures through the season feed, and repeating them here would ship the
/// same rows twice for a card that draws "2 of 3".
final class MyDailyChallengeDto {
  /// Creates the challenge reading.
  const MyDailyChallengeDto({
    required this.day,
    required this.total,
    required this.predicted,
    required this.complete,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory MyDailyChallengeDto.fromJson(Map<String, Object?> json) {
    return MyDailyChallengeDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      day: (json['day'] as String?) ?? '',
      total: (json['total'] as int?) ?? 0,
      predicted: (json['predicted'] as int?) ?? 0,
      complete: (json['complete'] as bool?) ?? false,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The Riyadh day this reading is about, as `YYYY-MM-DD`.
  ///
  /// A plain date, not a timestamp: the day boundary is the server's, and an
  /// instant would invite the client to re-derive it in its own zone.
  final String day;

  /// How many fixtures the caller's seasons hold today.
  final int total;

  /// How many of them the caller has predicted.
  final int predicted;

  /// Whether today is covered in full. A day with no fixtures is never
  /// complete, so `total == 0` always carries `complete: false`.
  final bool complete;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'day': day,
    'total': total,
    'predicted': predicted,
    'complete': complete,
  };

  @override
  bool operator ==(Object other) =>
      other is MyDailyChallengeDto &&
      other.day == day &&
      other.total == total &&
      other.predicted == predicted &&
      other.complete == complete &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(day, total, predicted, complete, schemaVersion);
}
