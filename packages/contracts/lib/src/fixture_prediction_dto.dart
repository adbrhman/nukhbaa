/// Versioned wire shapes for the per-fixture Prediction context
/// (docs/project-context.md, Axiom 4 Amendment: `Prediction` is keyed by
/// `(fixture_id, participant_id)`, replacing the round-scoped
/// `SubmitPredictionCommandDto`/`PredictionDto` in `prediction_dto.dart`,
/// which stay on disk unchanged until their callers migrate — Phase 6/7 of
/// the amendment's rollout).
///
/// These are pure data shapes shared verbatim by client and server; this file
/// depends on nothing (Application ADR §3).
///
/// Integrity boundary (Axioms 2/5): the command carries only the user's
/// intent for one fixture (scoreline + double flag). No DTO here carries
/// points or any computed/competitive-record value — those are the
/// server-only Scoring phase.
library;

/// The request body of the fixture-prediction submit/amend command. The
/// fixture is named in the path; the participant is resolved server-side
/// from the verified principal (never a body field — Security ADR §2 /
/// Axiom 2).
final class FixturePredictionCommandDto {
  /// Creates a fixture-prediction command DTO.
  const FixturePredictionCommandDto({
    required this.homeGoals,
    required this.awayGoals,
    this.isDouble = false,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads and [isDouble] to `false` when absent.
  factory FixturePredictionCommandDto.fromJson(Map<String, Object?> json) {
    return FixturePredictionCommandDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      homeGoals: json['home_goals']! as int,
      awayGoals: json['away_goals']! as int,
      isDouble: (json['is_double'] as bool?) ?? false,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The predicted goals for the home side.
  final int homeGoals;

  /// The predicted goals for the away side.
  final int awayGoals;

  /// Whether the caller marks this fixture as their double for the UTC day
  /// (the cross-fixture "at most one per day" cap is enforced server-side,
  /// not by this DTO).
  final bool isDouble;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'home_goals': homeGoals,
    'away_goals': awayGoals,
    'is_double': isDouble,
  };

  @override
  bool operator ==(Object other) =>
      other is FixturePredictionCommandDto &&
      other.homeGoals == homeGoals &&
      other.awayGoals == awayGoals &&
      other.isDouble == isDouble &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(homeGoals, awayGoals, isDouble, schemaVersion);
}

/// The wire shape of a stored fixture prediction (read projection of the
/// domain `FixturePrediction`).
///
/// Carries the participant + fixture binding, the submission instant (a
/// persistence-level fact, not a domain field — mirroring how `submittedAt`
/// was handled for the round-scoped `PredictionDto`), and the predicted
/// scoreline. Excludes any points/score/competitive-record value.
final class FixturePredictionDto {
  /// Creates a fixture-prediction DTO.
  const FixturePredictionDto({
    required this.id,
    required this.participantId,
    required this.fixtureId,
    required this.submittedAt,
    required this.homeGoals,
    required this.awayGoals,
    this.isDouble = false,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads and [isDouble] to `false` when absent.
  factory FixturePredictionDto.fromJson(Map<String, Object?> json) {
    return FixturePredictionDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      participantId: json['participant_id']! as String,
      fixtureId: json['fixture_id']! as String,
      submittedAt: json['submitted_at']! as String,
      homeGoals: json['home_goals']! as int,
      awayGoals: json['away_goals']! as int,
      isDouble: (json['is_double'] as bool?) ?? false,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The prediction id (UUID string).
  final String id;

  /// The owning participant id (UUID string).
  final String participantId;

  /// The predicted fixture's id (UUID string).
  final String fixtureId;

  /// The submission instant as an ISO-8601 UTC string.
  final String submittedAt;

  /// The predicted goals for the home side.
  final int homeGoals;

  /// The predicted goals for the away side.
  final int awayGoals;

  /// Whether this fixture is the caller's double for the UTC day.
  final bool isDouble;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'participant_id': participantId,
    'fixture_id': fixtureId,
    'submitted_at': submittedAt,
    'home_goals': homeGoals,
    'away_goals': awayGoals,
    'is_double': isDouble,
  };

  @override
  bool operator ==(Object other) =>
      other is FixturePredictionDto &&
      other.id == id &&
      other.participantId == participantId &&
      other.fixtureId == fixtureId &&
      other.submittedAt == submittedAt &&
      other.homeGoals == homeGoals &&
      other.awayGoals == awayGoals &&
      other.isDouble == isDouble &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    participantId,
    fixtureId,
    submittedAt,
    homeGoals,
    awayGoals,
    isDouble,
    schemaVersion,
  );
}
