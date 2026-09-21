/// Body of `GET /me/favorite-teams` and of both directions of
/// `PUT /me/favorite-teams` (plan P3-1): the ids of the teams the caller
/// follows, at most three, in the order chosen.
///
/// A missing or malformed list reads as empty: a client never invents a
/// team the server did not answer.
final class FavoriteTeamsDto {
  /// Creates the set.
  const FavoriteTeamsDto({
    required this.teamIds,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory FavoriteTeamsDto.fromJson(Map<String, Object?> json) {
    final raw = json['team_ids'];
    return FavoriteTeamsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      teamIds: raw is List<Object?>
          ? <String>[
              for (final id in raw)
                if (id is String) id,
            ]
          : const <String>[],
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The followed teams' ids (UUID strings), in the order chosen.
  final List<String> teamIds;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'team_ids': teamIds,
  };

  @override
  bool operator ==(Object other) {
    if (other is! FavoriteTeamsDto ||
        other.schemaVersion != schemaVersion ||
        other.teamIds.length != teamIds.length) {
      return false;
    }
    for (var i = 0; i < teamIds.length; i++) {
      if (other.teamIds[i] != teamIds[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(teamIds));
}
