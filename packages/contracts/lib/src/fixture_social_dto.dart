/// Versioned wire shapes for the fixture-scoped Social (Tier-3) context (API
/// ADR §4; docs/project-context.md, Axiom 4 Amendment — the per-fixture
/// sibling of `social_dto.dart`).
library;

/// The wire shape of one fixture-scoped reaction (read projection of the
/// domain `FixtureReaction`).
final class FixtureReactionDto {
  /// Creates a fixture-reaction DTO.
  const FixtureReactionDto({
    required this.id,
    required this.groupId,
    required this.fixtureId,
    required this.userId,
    required this.emoji,
    required this.reactedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixtureReactionDto.fromJson(Map<String, Object?> json) {
    return FixtureReactionDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      groupId: json['group_id']! as String,
      fixtureId: json['fixture_id']! as String,
      userId: json['user_id']! as String,
      emoji: json['emoji']! as String,
      reactedAt: json['reacted_at']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The reaction id (UUID string).
  final String id;

  /// The group this reaction is scoped to (UUID string).
  final String groupId;

  /// The fixture-result this reaction targets (UUID string).
  final String fixtureId;

  /// The reacting member's user id (UUID string).
  final String userId;

  /// The chosen emoji wire token (one of the closed set).
  final String emoji;

  /// When the reaction was made or last changed (UTC ISO-8601).
  final String reactedAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'group_id': groupId,
    'fixture_id': fixtureId,
    'user_id': userId,
    'emoji': emoji,
    'reacted_at': reactedAt,
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureReactionDto &&
      other.id == id &&
      other.groupId == groupId &&
      other.fixtureId == fixtureId &&
      other.userId == userId &&
      other.emoji == emoji &&
      other.reactedAt == reactedAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    groupId,
    fixtureId,
    userId,
    emoji,
    reactedAt,
    schemaVersion,
  );
}

/// The wire shape of a fixture's reactions within a group — the response of
/// `GET /groups/{id}/fixtures/{fixtureId}/reactions`.
final class FixtureReactionsDto {
  /// Creates a fixture-reactions DTO.
  const FixtureReactionsDto({
    required this.groupId,
    required this.fixtureId,
    required this.reactions,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixtureReactionsDto.fromJson(Map<String, Object?> json) {
    final raw = json['reactions']! as List<Object?>;
    return FixtureReactionsDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      groupId: json['group_id']! as String,
      fixtureId: json['fixture_id']! as String,
      reactions: raw
          .map(
            (e) => FixtureReactionDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The group this list is scoped to (UUID string).
  final String groupId;

  /// The fixture this list is scoped to (UUID string).
  final String fixtureId;

  /// The reactions, in the server-defined order (reactedAt ascending).
  final List<FixtureReactionDto> reactions;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'group_id': groupId,
    'fixture_id': fixtureId,
    'reactions': [for (final r in reactions) r.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureReactionsDto &&
      other.groupId == groupId &&
      other.fixtureId == fixtureId &&
      _listEquals(other.reactions, reactions) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(groupId, fixtureId, Object.hashAll(reactions), schemaVersion);

  static bool _listEquals(
    List<FixtureReactionDto> a,
    List<FixtureReactionDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
