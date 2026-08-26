#!/usr/bin/env bash
# apply_format_ci_fix.sh — تنسيق الملفات الـ19 التي أفشلت Verify formatting فقط، بدون لمس المنطق
set -euo pipefail

PROJECT_DIR="/home/dev/nukhbaa-backup-1787537565"
EXPECTED_HEAD="9e57a4a"
BACKUP_DIR="$PROJECT_DIR/.format-fix-backup-$(date +%Y%m%d-%H%M%S)"

FILES=(
  "apps/mobile/lib/features/admin/admin_providers.dart"
  "apps/mobile/lib/features/fixture_prediction/fixture_prediction_controller.dart"
  "apps/mobile/lib/features/fixture_prediction/fixture_prediction_screen.dart"
  "apps/mobile/lib/features/leaderboards/leaderboards_providers.dart"
  "apps/mobile/test/features/fixture_prediction/fixture_prediction_controller_test.dart"
  "apps/mobile/test/features/fixture_prediction/fixture_prediction_providers_test.dart"
  "apps/server/lib/composition/composition_root.dart"
  "apps/server/routes/seasons/[id]/fixtures/index.dart"
  "apps/server/routes/seasons/[id]/rounds/index.dart"
  "apps/server/test/routes/competition_seasons_test.dart"
  "apps/server/test/routes/season_fixtures_link_test.dart"
  "packages/api_client/test/competition_api_test.dart"
  "packages/api_client/test/prediction_api_test.dart"
  "packages/application/test/competition/browse_season_fixtures_test.dart"
  "packages/application/test/competition/link_fixture_to_season_test.dart"
  "packages/application/test/competition/start_season_test.dart"
  "packages/domain/test/notification/notification_kind_test.dart"
  "packages/infrastructure/lib/infrastructure.dart"
  "packages/infrastructure/test/prediction/postgres_fixture_prediction_repository_test.dart"
)

echo "== 1) الانتقال للمشروع =="
if [ ! -d "$PROJECT_DIR" ]; then
  echo "STOP: المسار غير موجود: $PROJECT_DIR"
  exit 1
fi
cd "$PROJECT_DIR"

echo "== 2) حالة git الحالية =="
git status --short
echo "---"
git log --oneline -5

echo "== 3) التحقق من نقطة البداية المتوقعة =="
CURRENT_HEAD="$(git rev-parse --short HEAD)"
if [ "$CURRENT_HEAD" != "$EXPECTED_HEAD" ]; then
  echo "STOP: HEAD الحالي ($CURRENT_HEAD) لا يطابق المتوقع ($EXPECTED_HEAD)."
  exit 1
fi

echo "== 4) التحقق من وجود عامل dart =="
if ! command -v dart >/dev/null 2>&1; then
  echo "STOP: أداة dart غير متوفرة في PATH."
  exit 1
fi

echo "== 5) التحقق من وجود شجرة عمل نظيفة (باستثناء apply_7_4_3_and_7_4_4.sh غير المتتبَّع) =="
DIRTY="$(git status --porcelain | grep -v 'apply_7_4_3_and_7_4_4.sh' | grep -v 'apply_format_ci_fix.sh' || true)"
if [ -n "$DIRTY" ]; then
  echo "STOP: هناك تغييرات محلية غير متوقعة قبل بدء السكربت."
  echo "$DIRTY"
  exit 1
fi

echo "== 6) التحقق من وجود كل ملف + نسخة احتياطية =="
mkdir -p "$BACKUP_DIR"
MISSING=0
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "STOP: ملف متوقع غير موجود: $f"
    MISSING=1
    continue
  fi
  mkdir -p "$BACKUP_DIR/$(dirname "$f")"
  cp "$f" "$BACKUP_DIR/$f"
done
if [ "$MISSING" -eq 1 ]; then
  echo "STOP: قائمة الملفات لا تطابق حالة المشروع الفعلية."
  exit 1
fi
echo "نسخة احتياطية في: $BACKUP_DIR"

echo "== 7) تشغيل dart format على الملفات الـ19 فقط =="
dart format "${FILES[@]}"

echo "== 8) عرض التغييرات =="
git diff --stat

echo "== 9) تحقق نهائي =="
if dart format --output=none --set-exit-if-changed "${FILES[@]}"; then
  echo "OK: الملفات الـ19 مطابقة الآن لتنسيق dart format."
else
  echo "STOP: ما زال هناك تنسيق غير متوافق."
  exit 1
fi

echo "== SUMMARY =="
echo "المرحلة: إصلاح Verify formatting فقط — لا منطق تغيّر"
echo "عدد الملفات المُنسَّقة: ${#FILES[@]}"
echo "نسخة احتياطية: $BACKUP_DIR"
echo "commit/push: لم يُنفَّذ — القرار لك"
