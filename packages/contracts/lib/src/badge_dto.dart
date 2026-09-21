/// One catalog badge as the caller stands on it (P2-8).
///
/// [code] is the stored badge code, a storage contract that is never renamed;
/// the client names the badge in its own l10n and skips a code it does not
/// know. Versioned through the enclosing [MyBadgesDto].
final class BadgeDto {
  /// Creates a badge line.
  const BadgeDto({
    required this.code,
    required this.current,
    required this.target,
    this.unlockedAt,
  });

  /// Deserializes from a JSON map, tolerating missing keys.
  factory BadgeDto.fromJson(Map<String, Object?> json) {
    return BadgeDto(
      code: (json['code'] as String?) ?? '',
      current: (json['current'] as int?) ?? 0,
      target: (json['target'] as int?) ?? 1,
      unlockedAt: json['unlocked_at'] as String?,
    );
  }

  /// The stored badge code, e.g. `first_prediction`.
  final String code;

  /// How far the caller has come, never above [target].
  final int current;

  /// The count at which the badge is earned, at least 1.
  final int target;

  /// When the badge was granted, as an ISO-8601 UTC instant, or null while
  /// it is not held.
  final String? unlockedAt;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'code': code,
    'current': current,
    'target': target,
    'unlocked_at': unlockedAt,
  };

  @override
  bool operator ==(Object other) =>
      other is BadgeDto &&
      other.code == code &&
      other.current == current &&
      other.target == target &&
      other.unlockedAt == unlockedAt;

  @override
  int get hashCode => Object.hash(code, current, target, unlockedAt);
}

/// Response body of `GET /me/badges`.
///
/// The whole catalog, in catalog order, each badge with the caller's
/// progress. A badge is held when its [BadgeDto.unlockedAt] is set; the
/// server grants it, the client only draws it.
final class MyBadgesDto {
  /// Creates the reading.
  const MyBadgesDto({
    required this.badges,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, tolerating older schema versions.
  factory MyBadgesDto.fromJson(Map<String, Object?> json) {
    final raw = (json['badges'] as List<Object?>?) ?? const <Object?>[];
    return MyBadgesDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      badges: raw
          .map(
            (e) => BadgeDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// Every catalog badge, in catalog order.
  final List<BadgeDto> badges;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'badges': [for (final b in badges) b.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! MyBadgesDto ||
        other.schemaVersion != schemaVersion ||
        other.badges.length != badges.length) {
      return false;
    }
    for (var i = 0; i < badges.length; i++) {
      if (other.badges[i] != badges[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(badges), schemaVersion);
}
