"""
Task 5 — الخطوة الثالثة: إكمال ربط composition_root.dart (5 تعديلات متبقية).
شغّله من جذر المشروع بعد نجاح fix_task5_step2.py.

الاستخدام:
    cd ~/nukhbaa
    python3 fix_task5_step3.py
"""

import pathlib


def patch_one(path, old, new, label):
    p = pathlib.Path(path)
    s = p.read_text()
    count = s.count(old)
    if count != 1:
        print(f"SKIP ({label}): expected 1 match, got {count}")
        print(f"  looking for: {old[:80]!r}")
        return False
    s = s.replace(old, new)
    p.write_text(s)
    print(f"OK ({label})")
    return True


path = "apps/server/lib/composition/composition_root.dart"

patch_one(
    path,
    "required this.getRoundScores,\n",
    "required this.getRoundScores,\n    required this.getRoundReport,\n",
    "constructor required-list",
)

patch_one(
    path,
    "GetRoundScores? getRoundScores,\n",
    "GetRoundScores? getRoundScores,\n    GetRoundReport? getRoundReport,\n",
    "forTesting optional param",
)

patch_one(
    path,
    "getRoundScores = getRoundScores ?? _absentGetRoundScores(),\n",
    "getRoundScores = getRoundScores ?? _absentGetRoundScores(),\n"
    "       getRoundReport = getRoundReport ?? _absentGetRoundReport(),\n",
    "forTesting initializer",
)

patch_one(
    path,
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
    "_absentGetRoundReport method",
)

patch_one(
    path,
    "final GetRoundScores getRoundScores;\n",
    "final GetRoundScores getRoundScores;\n\n"
    "  /// Reads a round's aggregated report (correct/incorrect counts + points)\n"
    "  /// — same visibility gate as [getRoundScores] (Task 5).\n"
    "  final GetRoundReport getRoundReport;\n",
    "field declaration",
)

print("=== DONE (راجع أي سطر SKIP أعلاه وأرسله لي) ===")
