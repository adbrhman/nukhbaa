"""
Task 5 — إصلاح الخطوة الثانية (composition_root + api_client + admin_providers).
شغّله من جذر المشروع بعد فشل apply_task5.py عند composition_root.dart.

الاستخدام:
    cd ~/nukhbaa
    python3 fix_task5_step2.py
"""

import re
import pathlib


def exact_patch(path, edits, label):
    p = pathlib.Path(path)
    s = p.read_text()
    for old, new in edits:
        count = s.count(old)
        if count != 1:
            print(f"SKIP ({label}): expected 1 match, got {count} in {path}")
            print(f"  looking for: {old[:80]!r}")
            return False
        s = s.replace(old, new)
    p.write_text(s)
    print(f"OK ({label}): {path}")
    return True


# 1) composition_root.dart — مطابقة مرنة عبر regex بدل نص حرفي
path = "apps/server/lib/composition/composition_root.dart"
p = pathlib.Path(path)
s = p.read_text()

pattern = re.compile(
    r"^([ \t]*)getRoundScores:\s*GetRoundScores\(\s*"
    r"competitionRepository:\s*competitionRepository,\s*"
    r"scoreRepository:\s*scoreRepository,\s*\),",
    re.MULTILINE,
)
matches = list(pattern.finditer(s))
if len(matches) != 1:
    print(f"SKIP (composition_root): expected 1 regex match, got {len(matches)}")
    print("أرسل لي: grep -n -A5 'getRoundScores: GetRoundScores(' apps/server/lib/composition/composition_root.dart")
else:
    m = matches[0]
    indent = m.group(1)
    insertion = (
        f"\n{indent}getRoundReport: GetRoundReport(\n"
        f"{indent}  competitionRepository: competitionRepository,\n"
        f"{indent}  scoreRepository: scoreRepository,\n"
        f"{indent}),"
    )
    s = s[: m.end()] + insertion + s[m.end() :]
    p.write_text(s)
    print(f"OK (composition_root): production wiring inserted (indent={len(indent)} spaces)")

# 2) api_client
exact_patch(
    "packages/api_client/lib/src/competition_api.dart",
    [
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
    ],
    "api_client",
)

# 3) mobile admin controller
exact_patch(
    "apps/mobile/lib/features/admin/admin_providers.dart",
    [
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
    ],
    "admin_providers",
)

print("=== DONE (راجع أي سطر SKIP أعلاه) ===")
