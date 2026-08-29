#!/usr/bin/env bash
set -euo pipefail
cd /home/dev/nukhbaa-backup-1787537565

python3 << 'PY'
path = "apps/server/lib/http/competition_dto_mapper.dart"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

if "activeSeasonToDto" in content:
    print("SKIP: activeSeasonToDto موجودة مسبقًا")
else:
    addition = '''
/// Projects a [ParticipantSeasonFeedEntry] onto its wire shape
/// [ActiveSeasonDto] (`GET /me/active-seasons`, the participant-scoped "my
/// active seasons" read -- docs/project-context.md, Axiom 4 Amendment). The
/// client fans out per season to the existing [BrowseSeasonFixtures] read
/// (`GET /seasons/{id}/fixtures`), unchanged by this projection.
ActiveSeasonDto activeSeasonToDto(ParticipantSeasonFeedEntry entry) {
  return ActiveSeasonDto(
    competitionId: entry.competitionId.value,
    competitionName: entry.competitionName,
    seasonId: entry.seasonId.value,
    seasonLabel: entry.seasonLabel,
    startAt: entry.startAt.toIso8601String(),
    endAt: entry.endAt.toIso8601String(),
  );
}
'''
    content = content.rstrip("\n") + "\n" + addition
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("OK: activeSeasonToDto مضافة")
PY

echo "== flutter analyze apps/server =="
if flutter analyze apps/server; then
  ANALYZE_STATUS="نجح"
else
  ANALYZE_STATUS="فشل"
fi

echo "== flutter test apps/server =="
if flutter test apps/server; then
  TEST_STATUS="نجح"
else
  TEST_STATUS="فشل"
fi

if [ "$ANALYZE_STATUS" = "نجح" ] && [ "$TEST_STATUS" = "نجح" ]; then
  cat >> docs/checkpoints/session-log.md << EOF
- [$(date +%H:%M)] إصلاح: إضافة activeSeasonToDto (mapper) لتحويل ParticipantSeasonFeedEntry إلى ActiveSeasonDto | ملف: apps/server/lib/http/competition_dto_mapper.dart | اختبار: نجح
EOF
  git add -A
  git commit -m "feat: add activeSeasonToDto mapper (GET /me/active-seasons prep)"
  git log --oneline -1
  echo "✅ تم الالتزام محليًا — بانتظار إذن push."
else
  echo "❌ توقف: analyze=$ANALYZE_STATUS test=$TEST_STATUS — لا commit."
  exit 1
fi
