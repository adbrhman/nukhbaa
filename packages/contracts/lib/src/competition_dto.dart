/// Versioned wire shapes for the Competition context (API ADR, Section 4: DTOs
/// are decoupled from the schema and carry a schema version so client and
/// archived payloads evolve safely).
///
/// These are pure data shapes shared verbatim by client and server; this file
/// depends on nothing (Application ADR, Section 3). They are *read* projections
/// — a command handler returns them, a client renders them — and deliberately
/// carry only stable, safe identity/structure facts, never internal state.
library;

/// The wire shape of a competition (read projection).
final class CompetitionDto {
  /// Creates a competition DTO.
  const CompetitionDto({
    required this.id,
    required this.name,
    required this.format,
    required this.visibility,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory CompetitionDto.fromJson(Map<String, Object?> json) {
    return CompetitionDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      name: json['name']! as String,
      format: json['format']! as String,
      visibility: json['visibility']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The competition id (UUID string).
  final String id;

  /// The display name.
  final String name;

  /// The game-format token (e.g. `football_scoreline`).
  final String format;

  /// The visibility token (`public` / `private`).
  final String visibility;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'name': name,
    'format': format,
    'visibility': visibility,
  };

  @override
  bool operator ==(Object other) =>
      other is CompetitionDto &&
      other.id == id &&
      other.name == name &&
      other.format == format &&
      other.visibility == visibility &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(id, name, format, visibility, schemaVersion);
}

/// The wire shape of a competition season (read projection).
final class SeasonDto {
  /// Creates a season DTO.
  const SeasonDto({
    required this.id,
    required this.competitionId,
    required this.label,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory SeasonDto.fromJson(Map<String, Object?> json) {
    return SeasonDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      competitionId: json['competition_id']! as String,
      label: json['label']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The season id (UUID string).
  final String id;

  /// The owning competition id (UUID string).
  final String competitionId;

  /// The display label (e.g. "2026/27").
  final String label;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'competition_id': competitionId,
    'label': label,
  };

  @override
  bool operator ==(Object other) =>
      other is SeasonDto &&
      other.id == id &&
      other.competitionId == competitionId &&
      other.label == label &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(id, competitionId, label, schemaVersion);
}

/// The wire shape of a round (read projection).
///
/// Intentionally excludes the frozen ruleset snapshot: the snapshot is an
/// internal, Scoring-owned structure (Application ADR, Section 2.10), not part
/// of the client-facing round read model. Only the ruleset *version* is exposed
/// so a client can display "rules v3" without receiving the opaque payload.
final class RoundDto {
  /// Creates a round DTO.
  const RoundDto({
    required this.id,
    required this.seasonId,
    required this.sequence,
    required this.predictionDeadline,
    required this.status,
    required this.rulesetVersion,
    this.isPredictable = false,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map. `is_predictable` defaults to `false`
  /// (fail-closed) for legacy payloads written before the sequential-round
  /// gate existed.
  factory RoundDto.fromJson(Map<String, Object?> json) {
    return RoundDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      seasonId: json['season_id']! as String,
      sequence: json['sequence']! as int,
      predictionDeadline: json['prediction_deadline']! as String,
      status: json['status']! as String,
      rulesetVersion: json['ruleset_version']! as int,
      isPredictable: (json['is_predictable'] as bool?) ?? false,
    );
  }

  /// The current schema version for this DTO. Bumped to 2 for the
  /// `is_predictable` field (the sequential-round gate — product decision,
  /// 2026-08-14); `fromJson` defaults a legacy (v1) or absent
  /// `schema_version` to 1, and a missing `is_predictable` to `false`
  /// (fail-closed), so older payloads keep decoding.
  static const int currentSchemaVersion = 2;

  /// The round id (UUID string).
  final String id;

  /// The owning season id (UUID string).
  final String seasonId;

  /// The 1-based ordinal within the season.
  final int sequence;

  /// The prediction deadline as an ISO-8601 UTC string.
  final String predictionDeadline;

  /// The lifecycle status token (`open` / `locked` / `scored`).
  final String status;

  /// The version of the ruleset frozen for this round.
  final int rulesetVersion;

  /// Whether the caller may currently submit a prediction for this round —
  /// the sequential-round gate (product decision, 2026-08-14): `true` only
  /// when this round is itself `open` AND every earlier round (lower
  /// [sequence]) in the same season has already left `open`. This is
  /// STRICTER than `status == 'open'` alone, since a season's rounds are
  /// typically all opened ahead of time (see [SubmitPrediction]'s
  /// `isRoundPredictable`). The client should gate the "predict" affordance
  /// on this flag, not on [status], to avoid re-deriving a rule the server
  /// already enforces.
  final bool isPredictable;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'season_id': seasonId,
    'sequence': sequence,
    'prediction_deadline': predictionDeadline,
    'status': status,
    'ruleset_version': rulesetVersion,
    'is_predictable': isPredictable,
  };

  @override
  bool operator ==(Object other) =>
      other is RoundDto &&
      other.id == id &&
      other.seasonId == seasonId &&
      other.sequence == sequence &&
      other.predictionDeadline == predictionDeadline &&
      other.status == status &&
      other.rulesetVersion == rulesetVersion &&
      other.isPredictable == isPredictable &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    seasonId,
    sequence,
    predictionDeadline,
    status,
    rulesetVersion,
    isPredictable,
    schemaVersion,
  );
}

/// The wire shape of a participant enrolment (read projection).
final class ParticipantDto {
  /// Creates a participant DTO.
  const ParticipantDto({
    required this.id,
    required this.seasonId,
    required this.userId,
    required this.status,
    required this.joinedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory ParticipantDto.fromJson(Map<String, Object?> json) {
    return ParticipantDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      id: json['id']! as String,
      seasonId: json['season_id']! as String,
      userId: json['user_id']! as String,
      status: json['status']! as String,
      joinedAt: json['joined_at']! as String,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The participant id (UUID string).
  final String id;

  /// The season id (UUID string).
  final String seasonId;

  /// The enrolled user id (UUID string).
  final String userId;

  /// The enrolment status token (`active` / `withdrawn`).
  final String status;

  /// The enrolment instant as an ISO-8601 UTC string.
  final String joinedAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'id': id,
    'season_id': seasonId,
    'user_id': userId,
    'status': status,
    'joined_at': joinedAt,
  };

  @override
  bool operator ==(Object other) =>
      other is ParticipantDto &&
      other.id == id &&
      other.seasonId == seasonId &&
      other.userId == userId &&
      other.status == status &&
      other.joinedAt == joinedAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(id, seasonId, userId, status, joinedAt, schemaVersion);
}

/// The wire shape of a round↔fixture link (read projection).
final class RoundFixtureDto {
  /// Creates a round-fixture link DTO.
  const RoundFixtureDto({
    required this.roundId,
    required this.fixtureId,
    required this.displayOrder,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory RoundFixtureDto.fromJson(Map<String, Object?> json) {
    return RoundFixtureDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      roundId: json['round_id']! as String,
      fixtureId: json['fixture_id']! as String,
      displayOrder: json['display_order']! as int,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owning round id (UUID string).
  final String roundId;

  /// The referenced fixture id (UUID string).
  final String fixtureId;

  /// The 0-based presentation order within the round.
  final int displayOrder;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'round_id': roundId,
    'fixture_id': fixtureId,
    'display_order': displayOrder,
  };

  @override
  bool operator ==(Object other) =>
      other is RoundFixtureDto &&
      other.roundId == roundId &&
      other.fixtureId == fixtureId &&
      other.displayOrder == displayOrder &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(roundId, fixtureId, displayOrder, schemaVersion);
}

/// A round-fixture link enriched with its fixture-schedule identity (team
/// names + kickoff), for the client's prediction-form render (Session
/// decision 2026-08-07: `GET /rounds/{id}/fixtures` widened instead of a new
/// endpoint). [homeTeam]/[awayTeam]/[kickoffAt] are nullable — a linked
/// fixture with no registered schedule yet is legitimate (Axiom 3).
final class RoundFixtureCardDto {
  /// Creates a round-fixture card DTO.
  const RoundFixtureCardDto({
    required this.roundId,
    required this.fixtureId,
    required this.displayOrder,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory RoundFixtureCardDto.fromJson(Map<String, Object?> json) {
    return RoundFixtureCardDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      roundId: json['round_id']! as String,
      fixtureId: json['fixture_id']! as String,
      displayOrder: json['display_order']! as int,
      homeTeam: json['home_team'] as String?,
      awayTeam: json['away_team'] as String?,
      kickoffAt: json['kickoff_at'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owning round id (UUID string).
  final String roundId;

  /// The referenced fixture id (UUID string).
  final String fixtureId;

  /// The 0-based presentation order within the round.
  final int displayOrder;

  /// The home side's team name, or `null` if not yet scheduled.
  final String? homeTeam;

  /// The away side's team name, or `null` if not yet scheduled.
  final String? awayTeam;

  /// The kickoff time as an ISO 8601 UTC timestamp string, or `null` if not
  /// yet scheduled.
  final String? kickoffAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'round_id': roundId,
    'fixture_id': fixtureId,
    'display_order': displayOrder,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
  };

  @override
  bool operator ==(Object other) =>
      other is RoundFixtureCardDto &&
      other.roundId == roundId &&
      other.fixtureId == fixtureId &&
      other.displayOrder == displayOrder &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    roundId,
    fixtureId,
    displayOrder,
    homeTeam,
    awayTeam,
    kickoffAt,
    schemaVersion,
  );
}

/// A [SeasonFixture] link enriched with its fixture-schedule identity (team
/// names + kickoff), for the per-fixture Prediction browse read (Axiom 4
/// Amendment — the season-scoped sibling of [RoundFixtureCardDto]; the same
/// nullability contract, since the season-fixture link never verifies a
/// schedule exists — Axiom 3).
final class SeasonFixtureCardDto {
  /// Creates a season-fixture card DTO.
  const SeasonFixtureCardDto({
    required this.seasonId,
    required this.fixtureId,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoffAt,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory SeasonFixtureCardDto.fromJson(Map<String, Object?> json) {
    return SeasonFixtureCardDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      seasonId: json['season_id']! as String,
      fixtureId: json['fixture_id']! as String,
      homeTeam: json['home_team'] as String?,
      awayTeam: json['away_team'] as String?,
      kickoffAt: json['kickoff_at'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owning season id (UUID string).
  final String seasonId;

  /// The referenced fixture id (UUID string).
  final String fixtureId;

  /// The home side's team name, or `null` if not yet scheduled.
  final String? homeTeam;

  /// The away side's team name, or `null` if not yet scheduled.
  final String? awayTeam;

  /// The kickoff time as an ISO 8601 UTC timestamp string, or `null` if not
  /// yet scheduled.
  final String? kickoffAt;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'season_id': seasonId,
    'fixture_id': fixtureId,
    'home_team': homeTeam,
    'away_team': awayTeam,
    'kickoff_at': kickoffAt,
  };

  @override
  bool operator ==(Object other) =>
      other is SeasonFixtureCardDto &&
      other.seasonId == seasonId &&
      other.fixtureId == fixtureId &&
      other.homeTeam == homeTeam &&
      other.awayTeam == awayTeam &&
      other.kickoffAt == kickoffAt &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    seasonId,
    fixtureId,
    homeTeam,
    awayTeam,
    kickoffAt,
    schemaVersion,
  );
}

/// One card in the unified matches feed (`GET /feed/matches` — the
/// server-side aggregate read replacing the client-side competition → season
/// → round → fixtures drill-down). Reuses [RoundFixtureCardDto]'s nested
/// shape verbatim (same nullability contract, same Axiom 3 rationale) so the
/// per-fixture fields never drift from `GET /rounds/{id}/fixtures`.
final class MatchFeedItemDto {
  /// Creates a match-feed item DTO.
  const MatchFeedItemDto({
    required this.competitionName,
    required this.roundId,
    required this.rulesetVersion,
    required this.fixture,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory MatchFeedItemDto.fromJson(Map<String, Object?> json) {
    return MatchFeedItemDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      competitionName: json['competition_name']! as String,
      roundId: json['round_id']! as String,
      rulesetVersion: json['ruleset_version']! as int,
      fixture: RoundFixtureCardDto.fromJson(
        (json['fixture']! as Map<Object?, Object?>).cast<String, Object?>(),
      ),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owning competition's display name.
  final String competitionName;

  /// The owning round id (UUID string).
  final String roundId;

  /// The round's frozen ruleset version.
  final int rulesetVersion;

  /// The fixture card (team names + kickoff, nullable per Axiom 3).
  final RoundFixtureCardDto fixture;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'competition_name': competitionName,
    'round_id': roundId,
    'ruleset_version': rulesetVersion,
    'fixture': fixture.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is MatchFeedItemDto &&
      other.competitionName == competitionName &&
      other.roundId == roundId &&
      other.rulesetVersion == rulesetVersion &&
      other.fixture == fixture &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    competitionName,
    roundId,
    rulesetVersion,
    fixture,
    schemaVersion,
  );
}

/// The request body of `POST /seasons/{id}/rounds` (command intent
/// `OpenRound`, admin-only). The season id travels in the path, never here.
final class OpenRoundRequestDto {
  /// Creates an open-round request body.
  const OpenRoundRequestDto({
    required this.sequence,
    required this.predictionDeadline,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map. A missing field surfaces as an explicit
  /// `null` so the use-case reports the validation failure rather than
  /// throwing at parse time.
  factory OpenRoundRequestDto.fromJson(Map<String, Object?> json) {
    return OpenRoundRequestDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      sequence: json['sequence'] as int?,
      predictionDeadline: json['prediction_deadline'] as String?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The 1-based ordinal of the round within its season.
  final int? sequence;

  /// The prediction deadline as an ISO 8601 timestamp string.
  final String? predictionDeadline;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'sequence': sequence,
    'prediction_deadline': predictionDeadline,
  };

  @override
  bool operator ==(Object other) =>
      other is OpenRoundRequestDto &&
      other.sequence == sequence &&
      other.predictionDeadline == predictionDeadline &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(sequence, predictionDeadline, schemaVersion);
}

/// The request body of `POST /rounds/{id}/fixtures` (command intent
/// `LinkFixtureToRound`, admin-only). The round id travels in the path.
final class LinkFixtureToRoundRequestDto {
  /// Creates a link-fixture-to-round request body.
  const LinkFixtureToRoundRequestDto({
    required this.fixtureId,
    required this.displayOrder,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map.
  factory LinkFixtureToRoundRequestDto.fromJson(Map<String, Object?> json) {
    return LinkFixtureToRoundRequestDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id'] as String?,
      displayOrder: json['display_order'] as int?,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture id to link (UUID string).
  final String? fixtureId;

  /// The 0-based presentation order within the round.
  final int? displayOrder;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'display_order': displayOrder,
  };

  @override
  bool operator ==(Object other) =>
      other is LinkFixtureToRoundRequestDto &&
      other.fixtureId == fixtureId &&
      other.displayOrder == displayOrder &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(fixtureId, displayOrder, schemaVersion);
}
