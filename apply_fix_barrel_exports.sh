#!/usr/bin/env bash
# Fix — Axiom 4 Amendment barrel-file exports.
# Phases 1-4's sed inserts were anchor-based (insert *before* a specific
# existing line) and failed SILENTLY if that anchor text didn't match your
# working copy exactly — sed doesn't error on a no-match, it just does
# nothing. Confirmed via grep: none of domain.dart / contracts.dart /
# application.dart / infrastructure.dart contain the new exports, which is
# why apps/server (Phase 5) cannot see any of the new types.
#
# This script does NOT touch anchors. For each new source file, it first
# verifies the file actually exists on disk (if phases 1-4 truly ran, it
# will), then appends the missing `export` line to the end of the relevant
# barrel file — idempotent (grep -q guard), safe to re-run.
set -euo pipefail
cd "${1:-.}"

fail=0

# Usage: ensure_export <source-file-relative-to-lib> <barrel-file> <export-line>
ensure_export() {
  local src_check="$1"
  local barrel="$2"
  local export_line="$3"

  if [[ ! -f "$src_check" ]]; then
    echo "MISSING SOURCE FILE: $src_check — phases 1-4 did not actually create it." >&2
    echo "  -> re-run the phase script that should have created it before continuing." >&2
    fail=1
    return
  fi

  if [[ ! -f "$barrel" ]]; then
    echo "MISSING BARREL FILE: $barrel" >&2
    fail=1
    return
  fi

  if grep -qF "$export_line" "$barrel"; then
    echo "already present: $export_line  (in $barrel)"
    return
  fi

  printf '%s\n' "$export_line" >> "$barrel"
  echo "APPENDED: $export_line  ->  $barrel"
}

# --- packages/domain/lib/domain.dart ---
ensure_export \
  'packages/domain/lib/src/competition/fixture_lock.dart' \
  'packages/domain/lib/domain.dart' \
  "export 'src/competition/fixture_lock.dart';"

ensure_export \
  'packages/domain/lib/src/competition/season_fixture.dart' \
  'packages/domain/lib/domain.dart' \
  "export 'src/competition/season_fixture.dart';"

ensure_export \
  'packages/domain/lib/src/prediction/daily_double_policy.dart' \
  'packages/domain/lib/domain.dart' \
  "export 'src/prediction/daily_double_policy.dart';"

ensure_export \
  'packages/domain/lib/src/prediction/fixture_prediction.dart' \
  'packages/domain/lib/domain.dart' \
  "export 'src/prediction/fixture_prediction.dart';"

ensure_export \
  'packages/domain/lib/src/scoring/participant_fixture_score.dart' \
  'packages/domain/lib/domain.dart' \
  "export 'src/scoring/participant_fixture_score.dart';"

# --- packages/contracts/lib/contracts.dart ---
ensure_export \
  'packages/contracts/lib/src/fixture_prediction_dto.dart' \
  'packages/contracts/lib/contracts.dart' \
  "export 'src/fixture_prediction_dto.dart';"

ensure_export \
  'packages/contracts/lib/src/participant_fixture_score_dto.dart' \
  'packages/contracts/lib/contracts.dart' \
  "export 'src/participant_fixture_score_dto.dart';"

# --- packages/application/lib/application.dart ---
ensure_export \
  'packages/application/lib/src/prediction/fixture_prediction_view.dart' \
  'packages/application/lib/application.dart' \
  "export 'src/prediction/fixture_prediction_view.dart';"

ensure_export \
  'packages/application/lib/src/prediction/ports/fixture_prediction_repository.dart' \
  'packages/application/lib/application.dart' \
  "export 'src/prediction/ports/fixture_prediction_repository.dart';"

ensure_export \
  'packages/application/lib/src/prediction/submit_fixture_prediction.dart' \
  'packages/application/lib/application.dart' \
  "export 'src/prediction/submit_fixture_prediction.dart';"

ensure_export \
  'packages/application/lib/src/scoring/ports/fixture_score_repository.dart' \
  'packages/application/lib/application.dart' \
  "export 'src/scoring/ports/fixture_score_repository.dart';"

ensure_export \
  'packages/application/lib/src/scoring/score_fixture.dart' \
  'packages/application/lib/application.dart' \
  "export 'src/scoring/score_fixture.dart';"

# --- packages/infrastructure/lib/infrastructure.dart ---
ensure_export \
  'packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart' \
  'packages/infrastructure/lib/infrastructure.dart' \
  "export 'src/prediction/postgres_fixture_prediction_repository.dart';"

ensure_export \
  'packages/infrastructure/lib/src/scoring/postgres_fixture_score_repository.dart' \
  'packages/infrastructure/lib/infrastructure.dart' \
  "export 'src/scoring/postgres_fixture_score_repository.dart';"

if [[ "$fail" -ne 0 ]]; then
  echo ""
  echo "توقف: بعض الملفات المصدرية نفسها غير موجودة (وليست فقط غير مُصدَّرة)." >&2
  echo "راجع الرسائل أعلاه — أعد تشغيل سكربت المرحلة المعنية أولًا." >&2
  exit 1
fi

echo ""
echo "DONE — الآن نفّذ:"
echo "  flutter pub get"
echo "  dart analyze apps/server"
echo "  flutter test apps/server/test/routes/fixture_prediction_scoring_test.dart"
