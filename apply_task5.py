"""
Task 5 — تقرير الجولة: تصحيح الملفات الموجودة.
شغّله من جذر المشروع (~/nukhbaa) بعد فك ضغط task5_delivery.zip في نفس الجذر
(الملفات الجديدة تُنسخ تلقائيًا من الزيب على المسارات الصحيحة).

الاستخدام:
    cd ~/nukhbaa
    unzip -o task5_delivery.zip -d .
    python3 apply_task5.py
"""

import pathlib


def patch(path, edits):
    p = pathlib.Path(path)
    s = p.read_text()
    for old, new in edits:
        count = s.count(old)
        assert count == 1, f"{path}: expected 1 match, got {count}: {old[:60]!r}"
        s = s.replace(old, new)
    p.write_text(s)
    print(f"OK: {path} ({len(edits)} edits)")


# 1) domain barrel
patch("packages/domain/lib/domain.dart", [
    ("export 'src/scoring/round_score.dart';",
     "export 'src/scoring/round_report_entry.dart';\nexport 'src/scoring/round_score.dart';"),
])

# 2) application barrel
patch("packages/application/lib/application.dart", [
    ("export 'src/scoring/get_round_scores.dart';",
     "export 'src/scoring/get_round_report.dart';\nexport 'src/scoring/get_round_scores.dart';"),
])

# 3) contracts DTOs
patch("packages/contracts/lib/src/scoring_dto.dart", [
    (
"""  static bool _listEquals(List<RoundScoreDto> a, List<RoundScoreDto> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}""",
"""  static bool _listEquals(List<RoundScoreDto> a, List<RoundScoreDto> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// One participant's row in the round-report read (Task 5): aggregated
/// correct/incorrect fixture-grade counts plus the total points, grouped
/// server-side over the same scored data as [RoundScoreDto] (an element of
/// the response of `GET /rounds/{id}/report`).
final class RoundReportRowDto {
  /// Creates a round-report row DTO.
  const RoundReportRowDto({
    required this.participantId,
    required this.correctCount,
    required this.incorrectCount,
    required this.totalPoints,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory RoundReportRowDto.fromJson(Map<String, Object?> json) {
    return RoundReportRowDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      participantId: json['participant_id']! as String,
      correctCount: json['correct_count']! as int,
      incorrectCount: json['incorrect_count']! as int,
      totalPoints: json['total_points']! as int,
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The owning participant id (UUID string).
  final String participantId;

  /// Fixtures graded exact-scoreline or correct-outcome.
  final int correctCount;

  /// Fixtures graded incorrect.
  final int incorrectCount;

  /// The same derived total the round score carries.
  final int totalPoints;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'participant_id': participantId,
    'correct_count': correctCount,
    'incorrect_count': incorrectCount,
    'total_points': totalPoints,
  };

  @override
  bool operator ==(Object other) =>
      other is RoundReportRowDto &&
      other.participantId == participantId &&
      other.correctCount == correctCount &&
      other.incorrectCount == incorrectCount &&
      other.totalPoints == totalPoints &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    participantId,
    correctCount,
    incorrectCount,
    totalPoints,
    schemaVersion,
  );
}

/// The wire shape of the whole-round report read (the response of
/// `GET /rounds/{id}/report`): the round id and every participant's
/// [RoundReportRowDto]. A pure read projection — visibility gating lives in
/// the use-case, not this shape.
final class RoundReportDto {
  /// Creates a round-report DTO.
  const RoundReportDto({
    required this.roundId,
    required this.rows,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Deserializes from a JSON map, defaulting [schemaVersion] for legacy
  /// payloads that predate the field.
  factory RoundReportDto.fromJson(Map<String, Object?> json) {
    final rawRows = json['rows']! as List<Object?>;
    return RoundReportDto(
      schemaVersion: (json['schema_version'] as int?) ?? 1,
      roundId: json['round_id']! as String,
      rows: rawRows
          .map(
            (e) => RoundReportRowDto.fromJson(
              (e! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  /// The current schema version for this DTO.
  static const int currentSchemaVersion = 1;

  /// The round this report is for (UUID string).
  final String roundId;

  /// Every participant's aggregated row for the round.
  final List<RoundReportRowDto> rows;

  /// The schema version of this payload.
  final int schemaVersion;

  /// Serializes to a JSON-encodable map.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'round_id': roundId,
    'rows': [for (final r in rows) r.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RoundReportDto &&
      other.roundId == roundId &&
      _listEquals(other.rows, rows) &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(roundId, Object.hashAll(rows), schemaVersion);

  static bool _listEquals(
    List<RoundReportRowDto> a,
    List<RoundReportRowDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}""",
    ),
])

# 4) server mapper
patch("apps/server/lib/http/scoring_dto_mapper.dart", [
    (
"""Map<String, Object?> roundScoresToJson(
  String roundId,
  List<RoundScore> scores,
) {
  return RoundScoresDto(
    roundId: roundId,
    scores: [for (final score in scores) roundScoreToDto(score)],
  ).toJson();
}""",
"""Map<String, Object?> roundScoresToJson(
  String roundId,
  List<RoundScore> scores,
) {
  return RoundScoresDto(
    roundId: roundId,
    scores: [for (final score in scores) roundScoreToDto(score)],
  ).toJson();
}

/// Projects one [RoundReportEntry] onto its wire shape [RoundReportRowDto]
/// (Task 5). A pure server-computed read value, same integrity boundary as
/// [roundScoreToDto].
RoundReportRowDto roundReportEntryToDto(RoundReportEntry entry) {
  return RoundReportRowDto(
    participantId: entry.participantId.value,
    correctCount: entry.correctCount,
    incorrectCount: entry.incorrectCount,
    totalPoints: entry.totalPoints,
  );
}

/// Shapes every participant's [RoundReportEntry] for a round into the
/// whole-round report response [RoundReportDto].
Map<String, Object?> roundReportToJson(
  String roundId,
  List<RoundReportEntry> entries,
) {
  return RoundReportDto(
    roundId: roundId,
    rows: [for (final e in entries) roundReportEntryToDto(e)],
  ).toJson();
}""",
    ),
])

# 5) composition_root.dart — 6 insertion points
patch("apps/server/lib/composition/composition_root.dart", [
    ("required this.getRoundScores,\n",
     "required this.getRoundScores,\n    required this.getRoundReport,\n"),
    ("GetRoundScores? getRoundScores,\n",
     "GetRoundScores? getRoundScores,\n    GetRoundReport? getRoundReport,\n"),
    ("getRoundScores = getRoundScores ?? _absentGetRoundScores(),\n",
     "getRoundScores = getRoundScores ?? _absentGetRoundScores(),\n       getRoundReport = getRoundReport ?? _absentGetRoundReport(),\n"),
    (
"""  static GetRoundScores _absentGetRoundScores() => GetRoundScores(
    competitionRepository: _unwiredCompetitionRepository,
    scoreRepository: _unwiredScoreRepository,
  );""",
"""  static GetRoundScores _absentGetRoundScores() => GetRoundScores(
    competitionRepository: _unwiredCompetitionRepository,
    scoreRepository: _unwiredScoreRepository,
  );

  /// Backs the "absent" [GetRoundReport]: throws so a test that reaches an
  /// unwired report slice fails loudly instead of touching a real database.
  /// Shares the same throwing collaborators as the "absent" [GetRoundScores]
  /// (it gates and reads identically).
  static GetRoundReport _absentGetRoundReport() => GetRoundReport(
    competitionRepository: _unwiredCompetitionRepository,
    scoreRepository: _unwiredScoreRepository,
  );""",
    ),
    ("final GetRoundScores getRoundScores;\n",
     "final GetRoundScores getRoundScores;\n\n  /// Reads a round's aggregated report (correct/incorrect counts + points)\n  /// — same visibility gate as [getRoundScores] (Task 5).\n  final GetRoundReport getRoundReport;\n"),
    (
"""    getRoundScores: GetRoundScores(
      competitionRepository: competitionRepository,
      scoreRepository: scoreRepository,
    ),""",
"""    getRoundScores: GetRoundScores(
      competitionRepository: competitionRepository,
      scoreRepository: scoreRepository,
    ),
    getRoundReport: GetRoundReport(
      competitionRepository: competitionRepository,
      scoreRepository: scoreRepository,
    ),""",
    ),
])

# 6) api_client
patch("packages/api_client/lib/src/competition_api.dart", [
    (
"""  Future<Result<RoundScoresDto>> getRoundScores(String roundId) {
    return _transport.getObject<RoundScoresDto>(
      '/rounds/$roundId/scores',
      parse: RoundScoresDto.fromJson,
    );
  }
}""",
"""  Future<Result<RoundScoresDto>> getRoundScores(String roundId) {
    return _transport.getObject<RoundScoresDto>(
      '/rounds/$roundId/scores',
      parse: RoundScoresDto.fromJson,
    );
  }

  /// `GET /rounds/{id}/report` — every participant's correct/incorrect
  /// fixture-grade counts and total points for a **scored** round (Task 5).
  /// Same gates as [getRoundScores]: a not-yet-scored round is refused
  /// `409 scoring.round_not_scored`; a non-participant is refused
  /// `401 scoring.not_a_participant` (server-enforced).
  Future<Result<RoundReportDto>> getRoundReport(String roundId) {
    return _transport.getObject<RoundReportDto>(
      '/rounds/$roundId/report',
      parse: RoundReportDto.fromJson,
    );
  }
}""",
    ),
])

# 7) mobile controller
patch("apps/mobile/lib/features/admin/admin_providers.dart", [
    (
"""    final scores = (scoresResult as Ok<RoundScoresDto>).value;
    final predictions = (predictionsResult as Ok<List<PredictionDto>>).value;
    state = AsyncValue.data(
      buildRoundReport(scores: scores, rawPredictions: predictions),
    );
  }
}""",
"""    final scores = (scoresResult as Ok<RoundScoresDto>).value;
    final predictions = (predictionsResult as Ok<List<PredictionDto>>).value;
    state = AsyncValue.data(
      buildRoundReport(scores: scores, rawPredictions: predictions),
    );
  }
}

/// Owns the round-report **summary** read: fetches `GET /rounds/{id}/report`
/// directly (Task 5) — server-side aggregated correct/incorrect counts and
/// points, no client-side merge. Named "Summary" to avoid colliding with
/// [RoundReportController] (Task 4's grid — a client merge of two other
/// reads).
@riverpod
class RoundReportSummaryController extends _$RoundReportSummaryController {
  CompetitionApi get _api => ref.read(competitionApiProvider);

  @override
  AsyncValue<RoundReportDto>? build() => null;

  /// Loads the report summary for the scored round [roundId].
  Future<void> load(String roundId) async {
    state = const AsyncValue.loading();
    final result = await _api.getRoundReport(roundId);
    state = switch (result) {
      Ok<RoundReportDto>(:final value) => AsyncValue.data(value),
      Err<RoundReportDto>(:final error) => AsyncValue.error(
        error,
        StackTrace.current,
      ),
    };
  }
}""",
    ),
])

print("=== ALL PATCHES APPLIED ===")
