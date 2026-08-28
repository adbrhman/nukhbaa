#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(pwd)"
FILE="packages/application/lib/src/prediction/fixture_prediction_view.dart"
if [ ! -f "$FILE" ]; then
  echo "خطأ: لم يُعثر على $FILE من المسار الحالي ($REPO_ROOT). نفّذ من جذر المستودع." >&2
  exit 1
fi
python3 << 'PYEOF'
import sys
path = "packages/application/lib/src/prediction/fixture_prediction_view.dart"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
old = """import 'package:domain/domain.dart';

/// A read model that pairs a [FixturePrediction] with the submission instant
/// its repository stamped on it — the per-fixture sibling of [PredictionView]
/// (docs/project-context.md, Axiom 4 Amendment), for the same reason:
/// `FixturePrediction` carries no `submittedAt` (a persistence fact, not a
/// domain invariant), but the wire DTO needs one.
///
/// Pure and immutable; value-comparable by `(prediction, submittedAt)`.
final class FixturePredictionView {
  /// Pairs [prediction] with the UTC [submittedAt] instant it was stored under.
  const FixturePredictionView({
    required this.prediction,
    required this.submittedAt,
  });

  /// The fixture-prediction aggregate.
  final FixturePrediction prediction;

  /// The submission instant (UTC) the repository stamped on this prediction.
  /// For an amended prediction this is the amendment instant.
  final DateTime submittedAt;

  @override
  bool operator ==(Object other) =>
      other is FixturePredictionView &&
      other.prediction == prediction &&
      other.submittedAt == submittedAt;

  @override
  int get hashCode => Object.hash(prediction, submittedAt);
}
"""
new = """import 'package:domain/domain.dart';

/// A read model that pairs a [FixturePrediction] with the submission instant
/// its repository stamped on it — the per-fixture sibling of [PredictionView]
/// (docs/project-context.md, Axiom 4 Amendment), for the same reason:
/// `FixturePrediction` carries no `submittedAt` (a persistence fact, not a
/// domain invariant), but the wire DTO needs one.
///
/// Pure and immutable; value-comparable by `(prediction, submittedAt, seasonId)`.
final class FixturePredictionView {
  /// Pairs [prediction] with the UTC [submittedAt] instant it was stored
  /// under, and optionally [seasonId].
  const FixturePredictionView({
    required this.prediction,
    required this.submittedAt,
    this.seasonId,
  });

  /// The fixture-prediction aggregate.
  final FixturePrediction prediction;

  /// The submission instant (UTC) the repository stamped on this prediction.
  /// For an amended prediction this is the amendment instant.
  final DateTime submittedAt;

  /// The season this prediction belongs to, derived from
  /// `participant_id -> competition.participants.season_id` (a permanent,
  /// unambiguous N:1 relationship — not the M:N
  /// `competition.season_fixtures` link, which answers a different question).
  /// Populated only by [FixturePredictionRepository.listByUser], whose query
  /// joins `competition.participants`; null from every other repository
  /// method, whose queries do not select this column.
  final SeasonId? seasonId;

  @override
  bool operator ==(Object other) =>
      other is FixturePredictionView &&
      other.prediction == prediction &&
      other.submittedAt == submittedAt &&
      other.seasonId == seasonId;

  @override
  int get hashCode => Object.hash(prediction, submittedAt, seasonId);
}
"""
if old not in content:
    print("فشل: النص الأصلي غير مطابق في " + path, file=sys.stderr)
    sys.exit(1)
content = content.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("تم تعديل " + path)
PYEOF
echo "== flutter analyze packages/application =="
flutter analyze packages/application
echo "== flutter test packages/application =="
if flutter test packages/application; then
  TEST_STATUS="نجح"
else
  TEST_STATUS="فشل"
fi
mkdir -p docs/checkpoints
cat >> docs/checkpoints/session-log.md << EOF
- [$(date +%H:%M)] إصلاح: إضافة حقل seasonId اختياري إلى FixturePredictionView | ملف: packages/application/lib/src/prediction/fixture_prediction_view.dart | اختبار: ${TEST_STATUS}
EOF
if [ "$TEST_STATUS" = "فشل" ]; then
  echo "توقف: الاختبارات فشلت، لم يُنفَّذ commit. راجع المخرجات أعلاه وأرسلها." >&2
  exit 1
fi
git add -A
git commit -m "fix: add optional seasonId field to FixturePredictionView"
git log --oneline -1
