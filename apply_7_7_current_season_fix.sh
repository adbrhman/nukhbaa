#!/usr/bin/env bash
# تصحيح لاحق على apply_7_7_current_season_step1.sh:
# dart analyze كشف اثنين implementers إضافيين لـCompetitionRepository لم يكونا
# ظاهرين في الفحص الأول (server composition_root stub + route test harness).
# هذا السكربت يضيف findCurrentSeason فيهما فقط. آمن للتشغيل مرة واحدة.
set -euo pipefail

if [ ! -d "packages/domain" ] || [ ! -d "apps/server" ]; then
  echo "خطأ: شغّله من جذر الريبو." >&2
  exit 1
fi

BACKUP_DIR=".step-7-7-current-season-fix-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR/apps/server/lib/composition" "$BACKUP_DIR/apps/server/test/routes"
cp apps/server/lib/composition/composition_root.dart "$BACKUP_DIR/apps/server/lib/composition/"
cp apps/server/test/routes/competition_route_harness.dart "$BACKUP_DIR/apps/server/test/routes/"
echo "== نسخة احتياطية في: $BACKUP_DIR =="

python3 - <<'PYEOF'
import sys, pathlib

def apply(path, old, new, label):
    p = pathlib.Path(path)
    text = p.read_text(encoding="utf-8")
    if text.count(old) != 1:
        print(f"فشل: '{label}' في {path} — المطابقة ليست فريدة (found={text.count(old)}). توقف.", file=sys.stderr)
        sys.exit(1)
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"تم: {label} -> {path}")

# --- composition_root.dart: _UnwiredCompetitionRepository ------------------
apply(
    "apps/server/lib/composition/composition_root.dart",
    """  @override
  Future<Result<CompetitionSeason>> findSeason(SeasonId id) => _unwired();

  @override
  Future<Result<void>> saveRound(Round round) => _unwired();""",
    """  @override
  Future<Result<CompetitionSeason>> findSeason(SeasonId id) => _unwired();

  @override
  Future<Result<CompetitionSeason?>> findCurrentSeason({
    required CompetitionId competitionId,
    required DateTime nowUtc,
  }) => _unwired();

  @override
  Future<Result<void>> saveRound(Round round) => _unwired();""",
    "_UnwiredCompetitionRepository.findCurrentSeason",
)

# --- competition_route_harness.dart: InMemoryCompetitionRepository ---------
apply(
    "apps/server/test/routes/competition_route_harness.dart",
    """  @override
  Future<Result<List<Round>>> listSeasonRounds(SeasonId seasonId) async {
    // A season's rounds ordered by their 1-based sequence (matches""",
    """  @override
  Future<Result<CompetitionSeason?>> findCurrentSeason({
    required CompetitionId competitionId,
    required DateTime nowUtc,
  }) async {
    // The season of this competition whose window covers `nowUtc` (matches
    // `_findCurrentSeasonSql`: start_at <= now AND end_at > now), tie-broken
    // by earliest startAt then id. Absent -> a legitimate `Ok(null)`.
    final matches =
        [
          for (final s in seasons.values)
            if (s.competitionId.value == competitionId.value &&
                s.isCurrentAt(nowUtc))
              s,
        ]..sort((a, b) {
          final byStart = a.startAt.compareTo(b.startAt);
          return byStart != 0 ? byStart : a.id.value.compareTo(b.id.value);
        });
    return Result.ok(matches.isEmpty ? null : matches.first);
  }

  @override
  Future<Result<List<Round>>> listSeasonRounds(SeasonId seasonId) async {
    // A season's rounds ordered by their 1-based sequence (matches""",
    "InMemoryCompetitionRepository.findCurrentSeason",
)

print("== الاستبدالان (2) نجحا ==")
PYEOF

echo ""
echo "== التنسيق =="
dart format \
  apps/server/lib/composition/composition_root.dart \
  apps/server/test/routes/competition_route_harness.dart

echo ""
echo "== dart analyze (workspace كامل، كما في CI) =="
dart analyze --fatal-warnings .

echo ""
echo "== اختبارات server (dart test) =="
( cd apps/server && dart test )

echo ""
echo "== git diff --stat (تراكمي منذ بداية 7.7) =="
git diff --stat

echo ""
echo "تم بنجاح. لا commit تلقائي — راجع git diff ثم نفّذ الـcommit يدويًا إذا كانت النتائج نظيفة."
