/// Body of `GET /seasons/{id}/duel-wins`: how many duels each player of the
/// season won, by participant id. A player who won none is absent.
final class SeasonDuelWinsDto {
  /// Creates the answer.
  const SeasonDuelWinsDto({
    required this.wins,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys; a count that is
  /// not a positive integer is left out.
  factory SeasonDuelWinsDto.fromJson(Map<String, Object?> json) {
    final Object? raw = json['wins'];
    return SeasonDuelWinsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      wins: <String, int>{
        if (raw is Map<String, Object?>)
          for (final MapEntry<String, Object?> e in raw.entries)
            if (e.value is int && (e.value as int) > 0) e.key: e.value as int,
      },
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Participant id to duels won.
  final Map<String, int> wins;

  /// The schema version of this payload.
  final int schemaVersion;

  /// The duels [participantId] won; zero when none.
  int of(String participantId) => wins[participantId] ?? 0;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'wins': wins,
  };
}
