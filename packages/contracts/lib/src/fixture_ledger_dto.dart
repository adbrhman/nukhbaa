/// Versioned wire shapes for the fixture-scoped Ledger context (API ADR §4;
/// docs/project-context.md, Axiom 4 Amendment — the per-fixture sibling of
/// `ledger_dto.dart`).
///
/// Read-only on the wire (Axioms 2/5): the client never computes or submits a
/// point amount. The command that posts a scored fixture to the ledger
/// (`POST /fixtures/{id}/ledger`) has NO request body; its response is the
/// [PostFixtureToLedgerResponseDto] read shape. Names a participant and
/// fixture by id only (Axiom 4: no group reference).
library;

/// The wire shape of one immutable fixture-scoped ledger movement (read
/// projection of the domain `FixturePointEntry`).
final class FixturePointEntryDto {
  /// Creates a fixture-point-entry DTO.
  const FixturePointEntryDto({
    required this.id,
    required this.participantId,
    required this.fixtureId,
    required this.kind,
    required this.amount,
    required this.sourceRef,
    required this.occurredAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixturePointEntryDto.fromJson(Map<String, Object?> json) {
    return FixturePointEntryDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      participantId: json['participant_id']! as String,
      fixtureId: json['fixture_id']! as String,
      kind: json['kind']! as String,
      amount: json['amount']! as int,
      sourceRef: json['source_ref']! as String,
      occurredAt: json['occurred_at']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The entry's own id (UUID string).
  final String id;

  /// The owning participant id (UUID string).
  final String participantId;

  /// The fixture this movement derives from (UUID string).
  final String fixtureId;

  /// The entry-kind wire token: `fixture_score` or `correction`.
  final String kind;

  /// The signed point movement (server-computed).
  final int amount;

  /// The provenance handle.
  final String sourceRef;

  /// When the movement occurred (ISO-8601 UTC string).
  final String occurredAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'participant_id': participantId,
    'fixture_id': fixtureId,
    'kind': kind,
    'amount': amount,
    'source_ref': sourceRef,
    'occurred_at': occurredAt,
  };

  @override
  bool operator ==(Object other) =>
      other is FixturePointEntryDto &&
      other.id == id &&
      other.participantId == participantId &&
      other.fixtureId == fixtureId &&
      other.kind == kind &&
      other.amount == amount &&
      other.sourceRef == sourceRef &&
      other.occurredAt == occurredAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    participantId,
    fixtureId,
    kind,
    amount,
    sourceRef,
    occurredAt,
    schemaVersion,
  );
}

/// The wire shape echoed back after an admin posts a scored fixture to the
/// ledger (`POST /fixtures/{id}/ledger`). An **empty** `appendedEntries` list
/// means the fixture was already fully posted (idempotent replay — Axiom 4).
final class PostFixtureToLedgerResponseDto {
  /// Creates a post-fixture-to-ledger response DTO.
  const PostFixtureToLedgerResponseDto({
    required this.fixtureId,
    required this.appendedEntries,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory PostFixtureToLedgerResponseDto.fromJson(Map<String, Object?> json) {
    final raw = json['appended_entries']! as List<Object?>;
    return PostFixtureToLedgerResponseDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id']! as String,
      appendedEntries: raw
          .map(
            (e) => FixturePointEntryDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture that was posted to the ledger (UUID string).
  final String fixtureId;

  /// The entries appended by this post (empty on an idempotent replay).
  final List<FixturePointEntryDto> appendedEntries;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'appended_entries': [for (final e in appendedEntries) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is PostFixtureToLedgerResponseDto &&
      other.fixtureId == fixtureId &&
      _listEquals(other.appendedEntries, appendedEntries) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(fixtureId, Object.hashAll(appendedEntries), schemaVersion);

  static bool _listEquals(
    List<FixturePointEntryDto> a,
    List<FixturePointEntryDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
