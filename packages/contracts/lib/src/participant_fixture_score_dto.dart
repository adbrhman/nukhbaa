/// Versioned wire shapes for the per-fixture Scoring context
/// (docs/project-context.md, Axiom 4 Amendment: "ScoreFixture replaces
/// ScoreRound"; replaces `RoundScoreDto`/`RoundScoresDto` in
/// `scoring_dto.dart`, which stay on disk unchanged until their callers
/// migrate — Phase 6/7 of the amendment's rollout).
///
/// These are pure data shapes shared verbatim by client and server; this file
/// depends on nothing (Application ADR §3) — deliberately the same
/// grade/points shape as `FixtureScoreResultDto` in `scoring_dto.dart`
/// (every contracts file is self-contained, not cross-imported), since
/// scoring produces one identically-shaped grade+points pair whether the
/// aggregation window is a round or a single fixture.
///
/// Read-only surface (Axioms 2/5: no command DTO — a fixture is scored by an
/// admin/system command whose body carries no points).
library;

/// The wire shape of one participant's scored result for one fixture (read
/// projection of the domain `ParticipantFixtureScore`).
///
/// Carries the (participant, fixture) binding, the [rulesetVersion] that
/// governed the scoring (Axiom 5, reproducibility), and the graded
/// [result] (which already reflects the double multiplier when the
/// prediction was marked double). Carries **no** round or group reference
/// (Axiom 4) and no client-writable field.
final class ParticipantFixtureScoreDto {
  /// Creates a participant-fixture-score DTO.
  const ParticipantFixtureScoreDto({
    required this.fixtureId,
    required this.participantId,
    required this.rulesetVersion,
    required this.grade,
    required this.points,
    this.displayName = '',
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory ParticipantFixtureScoreDto.fromJson(Map<String, Object?> json) {
    return ParticipantFixtureScoreDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id']! as String,
      participantId: json['participant_id']! as String,
      rulesetVersion: json['ruleset_version']! as int,
      displayName: (json['display_name'] as String?) ?? '',
      grade: json['grade']! as String,
      points: json['points']! as int,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture this score is for (UUID string).
  final String fixtureId;

  /// The owning participant id (UUID string).
  final String participantId;

  /// The version of the frozen ruleset used to compute this score.
  final int rulesetVersion;

  /// The grade wire token: `exact_scoreline`, `correct_outcome`, `incorrect`,
  /// `missed`, or `pending`. Matches `FixtureScoreGrade.wireValue` in the
  /// domain.
  final String grade;

  /// The server-computed points awarded for this fixture under the frozen
  /// ruleset (non-negative; already reflects the double multiplier when the
  /// prediction was marked double).
  final int points;

  /// The participant's display name, joined server-side. Empty when
  /// unavailable.
  final String displayName;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'participant_id': participantId,
    'ruleset_version': rulesetVersion,
    'display_name': displayName,
    'grade': grade,
    'points': points,
  };

  @override
  bool operator ==(Object other) =>
      other is ParticipantFixtureScoreDto &&
      other.fixtureId == fixtureId &&
      other.participantId == participantId &&
      other.rulesetVersion == rulesetVersion &&
      other.grade == grade &&
      other.points == points &&
      other.displayName == displayName &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    fixtureId,
    participantId,
    rulesetVersion,
    grade,
    points,
    displayName,
    schemaVersion,
  );
}

/// The wire shape of the scored-results read for a whole fixture: the
/// fixture id and every participant's [ParticipantFixtureScoreDto] (the
/// response of e.g. `GET /fixtures/{id}/scores`). A pure read projection —
/// visibility gating lives in the use-case, not this shape.
final class FixtureScoresDto {
  /// Creates a fixture-scores DTO.
  const FixtureScoresDto({
    required this.fixtureId,
    required this.scores,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory FixtureScoresDto.fromJson(Map<String, Object?> json) {
    final rawScores = json['scores']! as List<Object?>;
    return FixtureScoresDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      fixtureId: json['fixture_id']! as String,
      scores: rawScores
          .map(
            (e) => ParticipantFixtureScoreDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The fixture this read is for (UUID string).
  final String fixtureId;

  /// Every participant's scored result for this fixture. Empty is
  /// legitimate (no predictions covered this fixture).
  final List<ParticipantFixtureScoreDto> scores;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'fixture_id': fixtureId,
    'scores': [for (final s in scores) s.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is FixtureScoresDto &&
      other.fixtureId == fixtureId &&
      _listEquals(other.scores, scores) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(fixtureId, Object.hashAll(scores), schemaVersion);

  static bool _listEquals(
    List<ParticipantFixtureScoreDto> a,
    List<ParticipantFixtureScoreDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
