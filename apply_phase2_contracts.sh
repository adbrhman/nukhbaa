#!/usr/bin/env bash
# Phase 2 — Contracts expand (Axiom 4 Amendment: fixture-level DTOs).
# Additive only: creates new DTO files + adds export lines to contracts.dart.
set -euo pipefail
cd "${1:-.}"

mkdir -p packages/contracts/lib/src packages/contracts/test

cat > 'packages/contracts/lib/src/fixture_prediction_dto.dart' <<'NUKHBA_EOF'
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
NUKHBA_EOF

cat > 'packages/contracts/lib/src/participant_fixture_score_dto.dart' <<'NUKHBA_EOF'
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
NUKHBA_EOF

cat > 'packages/contracts/test/fixture_prediction_dto_test.dart' <<'NUKHBA_EOF'
import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('FixturePredictionCommandDto', () {
    test('round-trips through JSON with snake_case keys', () {
      const dto = FixturePredictionCommandDto(
        homeGoals: 2,
        awayGoals: 1,
        isDouble: true,
      );
      final json = dto.toJson();
      expect(
        json.keys,
        containsAll(<String>[
          'schema_version',
          'home_goals',
          'away_goals',
          'is_double',
        ]),
      );
      expect(FixturePredictionCommandDto.fromJson(json), dto);
    });

    test('defaults is_double to false when absent (back-compat)', () {
      final decoded = FixturePredictionCommandDto.fromJson(const {
        'home_goals': 0,
        'away_goals': 0,
      });
      expect(decoded.isDouble, isFalse);
      expect(decoded.schemaVersion, 1);
    });

    test('body carries no fixture/participant field (both server-resolved)', () {
      const dto = FixturePredictionCommandDto(homeGoals: 1, awayGoals: 1);
      expect(dto.toJson().keys, isNot(contains('fixture_id')));
      expect(dto.toJson().keys, isNot(contains('participant_id')));
    });

    test('value equality is by field, not identity', () {
      const a = FixturePredictionCommandDto(homeGoals: 1, awayGoals: 0);
      const b = FixturePredictionCommandDto(homeGoals: 1, awayGoals: 0);
      const c = FixturePredictionCommandDto(homeGoals: 1, awayGoals: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('FixturePredictionDto', () {
    const dto = FixturePredictionDto(
      id: 'p1',
      participantId: 'part1',
      fixtureId: 'f1',
      submittedAt: '2026-08-01T12:00:00Z',
      homeGoals: 2,
      awayGoals: 0,
      isDouble: true,
    );

    test('round-trips through JSON', () {
      expect(FixturePredictionDto.fromJson(dto.toJson()), dto);
    });

    test('carries no round reference on the wire', () {
      expect(dto.toJson().keys, isNot(contains('round_id')));
    });

    test('defaults schema_version to 1 when absent (back-compat)', () {
      final decoded = FixturePredictionDto.fromJson(const {
        'id': 'p1',
        'participant_id': 'part1',
        'fixture_id': 'f1',
        'submitted_at': '2026-08-01T12:00:00Z',
        'home_goals': 1,
        'away_goals': 1,
      });
      expect(decoded.schemaVersion, 1);
      expect(decoded.isDouble, isFalse);
    });

    test('value equality is by field, not identity', () {
      final same = FixturePredictionDto.fromJson(dto.toJson());
      expect(same, dto);
      expect(same.hashCode, dto.hashCode);
    });
  });
}
NUKHBA_EOF

cat > 'packages/contracts/test/participant_fixture_score_dto_test.dart' <<'NUKHBA_EOF'
import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('ParticipantFixtureScoreDto', () {
    const dto = ParticipantFixtureScoreDto(
      fixtureId: 'f1',
      participantId: 'part1',
      rulesetVersion: 1,
      grade: 'exact_scoreline',
      points: 6,
      displayName: 'Ali',
    );

    test('round-trips through JSON', () {
      expect(ParticipantFixtureScoreDto.fromJson(dto.toJson()), dto);
    });

    test('carries no round reference on the wire', () {
      expect(dto.toJson().keys, isNot(contains('round_id')));
    });

    test('defaults display_name/schema_version when absent (back-compat)', () {
      final decoded = ParticipantFixtureScoreDto.fromJson(const {
        'fixture_id': 'f1',
        'participant_id': 'part1',
        'ruleset_version': 1,
        'grade': 'incorrect',
        'points': 0,
      });
      expect(decoded.displayName, '');
      expect(decoded.schemaVersion, 1);
    });

    test('value equality is by field, not identity', () {
      final same = ParticipantFixtureScoreDto.fromJson(dto.toJson());
      expect(same, dto);
      expect(same.hashCode, dto.hashCode);
    });
  });

  group('FixtureScoresDto', () {
    test('round-trips, preserving score order', () {
      const dto = FixtureScoresDto(
        fixtureId: 'f1',
        scores: [
          ParticipantFixtureScoreDto(
            fixtureId: 'f1',
            participantId: 'p1',
            rulesetVersion: 1,
            grade: 'exact_scoreline',
            points: 6,
          ),
          ParticipantFixtureScoreDto(
            fixtureId: 'f1',
            participantId: 'p2',
            rulesetVersion: 1,
            grade: 'incorrect',
            points: 0,
          ),
        ],
      );
      final decoded = FixtureScoresDto.fromJson(dto.toJson());
      expect(decoded, dto);
      expect(decoded.scores.first.participantId, 'p1');
      expect(decoded.scores.last.participantId, 'p2');
    });

    test('an empty score list is legitimate', () {
      const dto = FixtureScoresDto(fixtureId: 'f1', scores: []);
      final decoded = FixtureScoresDto.fromJson(dto.toJson());
      expect(decoded.scores, isEmpty);
    });
  });
}
NUKHBA_EOF

# --- تحديث exports في contracts.dart (إضافة فقط، لا حذف) ---
F=packages/contracts/lib/contracts.dart
grep -q "src/fixture_prediction_dto.dart" "$F" || \
  sed -i "\#export 'src/fixture_schedule_dto.dart';#i export 'src/fixture_prediction_dto.dart';" "$F"
grep -q "src/participant_fixture_score_dto.dart" "$F" || \
  sed -i "\#export 'src/prediction_dto.dart';#i export 'src/participant_fixture_score_dto.dart';" "$F"

echo "DONE — الآن نفّذ:"
echo "  flutter pub get"
echo "  dart analyze packages/contracts"
echo "  flutter test packages/contracts"
