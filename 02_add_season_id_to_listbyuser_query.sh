#!/usr/bin/env bash
set -euo pipefail

# يُنفَّذ من جذر المستودع: /home/dev/nukhbaa-backup-1787537565
REPO_ROOT="$(pwd)"
FILE="packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart"

if [ ! -f "$FILE" ]; then
  echo "خطأ: لم يُعثر على $FILE من المسار الحالي ($REPO_ROOT). نفّذ من جذر المستودع." >&2
  exit 1
fi

python3 << 'PYEOF'
import sys

path = "packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

old = """  // --------------------------------------------------------------------------
  // listByUser — the caller's own aggregated fixture-prediction history
  // (every fixture, every season the user has ever participated in) — the
  // per-fixture sibling of PostgresPredictionRepository.listByUser.
  // --------------------------------------------------------------------------

  // A user holds a DIFFERENT competition.participants row per season
  // (Database ADR §1), so this joins fixture_predictions -> participants on
  // user_id (not a single participant_id) to span every season the user has
  // ever played — mirrors PostgresPredictionRepository._selectByUserSql.
  // Ordered newest-first (history), then by id for a stable tie-break.
  static const String _selectByUserSql = '''
SELECT fp.id             AS id,
       fp.fixture_id     AS fixture_id,
       fp.participant_id AS participant_id,
       fp.home_goals     AS home_goals,
       fp.away_goals     AS away_goals,
       fp.is_double      AS is_double,
       fp.submitted_at   AS submitted_at
FROM prediction.fixture_predictions fp
JOIN competition.participants c ON c.id = fp.participant_id
WHERE c.user_id = @user_id
ORDER BY fp.submitted_at DESC, fp.id ASC
''';

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async {
    final result = await _connection.query(
      _selectByUserSql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapList(value),
    };
  }
"""

new = """  // --------------------------------------------------------------------------
  // listByUser — the caller's own aggregated fixture-prediction history
  // (every fixture, every season the user has ever participated in) — the
  // per-fixture sibling of PostgresPredictionRepository.listByUser.
  // --------------------------------------------------------------------------

  // A user holds a DIFFERENT competition.participants row per season
  // (Database ADR §1), so this joins fixture_predictions -> participants on
  // user_id (not a single participant_id) to span every season the user has
  // ever played — mirrors PostgresPredictionRepository._selectByUserSql.
  // Ordered newest-first (history), then by id for a stable tie-break.
  //
  // Also selects `c.season_id` (from `participants`, the permanent N:1 owner
  // of a prediction's season — not the M:N `competition.season_fixtures`
  // link, which answers a different question) to populate
  // `FixturePredictionView.seasonId`. Every other repository method leaves
  // that field null; only this query's row shape carries the column.
  static const String _selectByUserSql = '''
SELECT fp.id             AS id,
       fp.fixture_id     AS fixture_id,
       fp.participant_id AS participant_id,
       fp.home_goals     AS home_goals,
       fp.away_goals     AS away_goals,
       fp.is_double      AS is_double,
       fp.submitted_at   AS submitted_at,
       c.season_id       AS season_id
FROM prediction.fixture_predictions fp
JOIN competition.participants c ON c.id = fp.participant_id
WHERE c.user_id = @user_id
ORDER BY fp.submitted_at DESC, fp.id ASC
''';

  @override
  Future<Result<List<FixturePredictionView>>> listByUser(UserId userId) async {
    final result = await _connection.query(
      _selectByUserSql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapListWithSeason(value),
    };
  }

  // listByUser's row shape carries `season_id` (see the query above); every
  // other query in this repository does not select that column, so this
  // mapping is kept separate from the shared `_mapList` rather than adding a
  // conditional branch to it.
  Result<List<FixturePredictionView>> _mapListWithSeason(
    List<Map<String, dynamic>> rows,
  ) {
    final views = <FixturePredictionView>[];
    for (final row in rows) {
      final mapped = _mapOne(row);
      if (mapped is Err<FixturePredictionView?>) {
        return Result.err(mapped.error);
      }
      final view = (mapped as Ok<FixturePredictionView?>).value;
      if (view == null) {
        continue;
      }
      final rawSeasonId = row['season_id'];
      SeasonId? seasonId;
      if (rawSeasonId != null) {
        final seasonIdResult = SeasonId.tryParse(rawSeasonId.toString());
        if (seasonIdResult is Err<SeasonId>) {
          return Result.err(
            _corrupt(
              'fixture_predictions',
              'season_id',
              seasonIdResult.error.message,
            ),
          );
        }
        seasonId = (seasonIdResult as Ok<SeasonId>).value;
      }
      views.add(
        FixturePredictionView(
          prediction: view.prediction,
          submittedAt: view.submittedAt,
          seasonId: seasonId,
        ),
      );
    }
    return Result.ok(List<FixturePredictionView>.unmodifiable(views));
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

echo "== flutter analyze packages/infrastructure =="
flutter analyze packages/infrastructure

echo "== flutter test packages/infrastructure =="
if flutter test packages/infrastructure; then
  TEST_STATUS="نجح"
else
  TEST_STATUS="فشل"
fi

mkdir -p docs/checkpoints
cat >> docs/checkpoints/session-log.md << 'EOF'
- [$(date +%H:%M)] إصلاح: إضافة عمود season_id لاستعلام listByUser وتمريره إلى FixturePredictionView | ملف: packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart | اختبار: ${TEST_STATUS}
EOF

if [ "$TEST_STATUS" = "فشل" ]; then
  echo "توقف: الاختبارات فشلت، لم يُنفَّذ commit. راجع المخرجات أعلاه وأرسلها." >&2
  exit 1
fi

git add -A
git commit -m "fix: add season_id to listByUser query and pass to FixturePredictionView"
git log --oneline -1
