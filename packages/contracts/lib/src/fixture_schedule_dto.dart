/// Versioned wire shapes for the fixture-IDENTITY seam (API ADR §4: DTOs are
/// decoupled from the schema and carry a schema version so client and
/// archived payloads evolve safely).
///
/// These are pure data shapes shared verbatim by client and server; this file
/// depends on nothing (Application ADR §3).
///
/// Integrity boundary (Axiom 3; Next-Task decision 2026-07-11, option (a),
/// applied to schedule rather than outcome): a fixture's identity — which two
/// sides play and when — is admin-fed, never client-computed. It carries **no**
/// competition/round reference (the same fixture may be linked into many
/// rounds). [FixtureScheduleRequestDto] is the ONE client-supplied body shape,
/// reused unchanged for both registration (`POST /fixtures`, where the fixture
/// id is server-generated) and correction (`PUT /fixtures/{id}`, where the id
/// travels in the path) — mirroring the suspend/reinstate precedent in the
/// Admin Panel contracts (`SuspendUserRequestDto`): same body, the id/action
/// distinction lives in the route, never duplicated across two DTOs.
library;

/// The wire shape echoed back for a fixture's registered identity (the
/// response of both `POST /fixtures` and `PUT /fixtures/{id}`, and the read
/// projection of the domain `FixtureSchedule`).
///
/// Carries no competition/round reference (Axiom 3). [kickoffAt] is an ISO
/// 8601 UTC timestamp string — every DTO on the wire is String/int only, so a
/// `DateTime` field is never passed as a native type across the boundary.
final class FixtureScheduleDto {
  /// Creates a fixture-schedule DTO.
  const FixtureScheduleDto({
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixtureScheduleDto.fromJson(Map<String, Object?> json) {
    return FixtureScheduleDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id']! as String,
      homeTeam: json['home_team']! as String,
      awayTeam: json['away_team']! as String,
      kickoffAt: json['kickoff_at']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture id (UUID string).
  final String fixtureId;

  /// The home side's team name (server-trimmed, 1-120 characters).
  final String homeTeam;

  /// The away side's team name (server-trimmed, 1-120 characters, distinct
  /// from [homeTeam]).
  final String awayTeam;

  /// The kickoff time as an ISO 8601 UTC timestamp string.
  final String kickoffAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureScheduleDto &&
      other.fixtureId == fixtureId &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(fixtureId, homeTeam, awayTeam, kickoffAt, schemaVersion);
}

/// The request body of a fixture-identity registration/correction command
/// (`POST /fixtures` | `PUT /fixtures/{id}`, admin-only). The fixture id is
/// EITHER server-generated (register) OR taken from the path (correct) —
/// never from this body — so the same shape serves both routes (see the
/// library-level doc comment).
final class FixtureScheduleRequestDto {
  /// Creates a fixture-schedule request body.
  const FixtureScheduleRequestDto({
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field. A missing field surfaces as an explicit
  /// `null` so the use-case reports the validation failure (never a silent
  /// empty team name or fabricated kickoff time).
  factory FixtureScheduleRequestDto.fromJson(Map<String, Object?> json) {
    return FixtureScheduleRequestDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      homeTeam: json['home_team'] as String?,
      awayTeam: json['away_team'] as String?,
      kickoffAt: json['kickoff_at'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The home side's team name. Nullable on the wire only so a malformed body
  /// (missing field) can be reported as a validation failure by the use-case
  /// rather than throwing at parse time.
  final String? homeTeam;

  /// The away side's team name.
  final String? awayTeam;

  /// The kickoff time as an ISO 8601 timestamp string.
  final String? kickoffAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureScheduleRequestDto &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(homeTeam, awayTeam, kickoffAt, schemaVersion);
}
