/// The champions of the Elite Cup (migrations 0190 and 0204), as every player
/// reads them and as the admin's crowning panel lists them.
library;

/// One champion of one path of the Elite Cup of one month.
final class CupChampionDto {
  /// Creates the row.
  const CupChampionDto({
    required this.monthStart,
    required this.place,
    required this.how,
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.avatarUrl,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory CupChampionDto.fromJson(Map<String, Object?> json) => CupChampionDto(
    monthStart: (json['month_start'] as String?) ?? '',
    place: (json['place'] as int?) ?? 0,
    how: (json['how'] as String?) ?? '',
    userId: (json['user_id'] as String?) ?? '',
    displayName: (json['display_name'] as String?) ?? '',
    photoUrl: json['photo_url'] as String?,
    avatarUrl: json['avatar_url'] as String?,
  );

  /// The first day of the month of the cup (`YYYY-MM-DD`).
  final String monthStart;

  /// The path: 1 (the elite cup), 2 or 3.
  final int place;

  /// How the title was won: `final` or `walkover`.
  final String how;

  /// The champion.
  final String userId;

  /// The champion's display name.
  final String displayName;

  /// The server-relative URL of the picture an admin added, if any.
  final String? photoUrl;

  /// The server-relative URL of the champion's own avatar, if any.
  final String? avatarUrl;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'month_start': monthStart,
    'place': place,
    'how': how,
    'user_id': userId,
    'display_name': displayName,
    if (photoUrl != null) 'photo_url': photoUrl,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };
}

/// `GET /cup-champions`: the champions of the Elite Cup, newest month first.
final class CupChampionsDto {
  /// Creates the list.
  const CupChampionsDto({
    required this.champions,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory CupChampionsDto.fromJson(Map<String, Object?> json) =>
      CupChampionsDto(
        schemaVersion: (json['schema_version'] as int?) ?? 1,
        champions: [
          for (final Object? c in (json['champions'] as List<Object?>?) ?? [])
            if (c is Map<String, Object?>) CupChampionDto.fromJson(c),
        ],
      );

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The champions, newest month first, then by path.
  final List<CupChampionDto> champions;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'champions': [for (final CupChampionDto c in champions) c.toJson()],
  };
}
