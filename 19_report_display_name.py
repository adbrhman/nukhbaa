#!/usr/bin/env python3
"""19_report_display_name — «تقرير المباراة» يعرض الاسم لا المعرّف.

السلسلة كاملة أصلًا: adminGetParticipantDisplayNames -> fixtureScoresToJson
-> ParticipantFixtureScoreDto.displayName -> FixtureReportRow.displayName.
الودجت وحدها كانت ترسم row.participantId. إصلاح في طبقة العرض فقط.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path.home() / "nukhbaa-backup-1787537565"
assert ROOT.is_dir(), f"مسار المشروع غير موجود: {ROOT}"

TARGET = ROOT / "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart"
assert TARGET.is_file(), f"الملف غير موجود: {TARGET}"

src = TARGET.read_text(encoding="utf-8")

OLD = """          Expanded(
            child: Text(
              row.participantId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyLarge?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),"""

NEW = """          Expanded(
            child: Text(
              row.displayName.isNotEmpty
                  ? row.displayName
                  : _shortId(row.participantId),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyLarge?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),"""

assert src.count(OLD) == 1, f"مرساة الاسم غير فريدة: {src.count(OLD)}"
src = src.replace(OLD, NEW)

# مُساعِد الاحتياط: أول 8 محارف من UUID عند غياب الاسم.
HELPER_ANCHOR = """class _FixtureReportRowCard extends StatelessWidget {"""
HELPER = """/// الاحتياط حين لا يصل اسم معروض من الخادم: مقطع قصير من المعرّف بدل
/// UUID كامل يملأ السطر.
String _shortId(String participantId) => participantId.length <= 8
    ? participantId
    : '${participantId.substring(0, 8)}…';

class _FixtureReportRowCard extends StatelessWidget {"""

assert src.count(HELPER_ANCHOR) == 1, "مرساة الصنف غير فريدة"
assert "_shortId" not in src.split(HELPER_ANCHOR)[0], "المساعد موجود مسبقًا"
src = src.replace(HELPER_ANCHOR, HELPER, 1)

TARGET.write_text(src, encoding="utf-8")
print("✓ حُدِّث results_scoring_section.dart")


def run(cmd, cwd=ROOT):
    print(f"$ {cmd}")
    r = subprocess.run(cmd, shell=True, cwd=cwd)
    if r.returncode != 0:
        sys.exit(r.returncode)


run("dart format apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart")
run("cd apps/mobile && flutter analyze --no-fatal-infos lib/features/admin")
run("cd apps/mobile && flutter test --reporter=failures-only")

LOG = ROOT / "docs/checkpoints/session-log.md"
LOG.write_text(
    LOG.read_text(encoding="utf-8")
    + "\n2026-09-05 — 19_report_display_name: «تقرير المباراة» في لوحة المشرف كان "
    "يعرض participantId خامًا رغم أن displayName يصل فعليًا عبر السلسلة كاملة "
    "(adminGetParticipantDisplayNames -> fixtureScoresToJson -> "
    "ParticipantFixtureScoreDto.displayName -> FixtureReportRow.displayName)؛ "
    "_FixtureReportRowCard وحدها كانت ترسم المعرّف. صارت تعرض الاسم، ومع غيابه "
    "مقطعًا من ثمانية محارف بدل UUID كامل. تعديل في طبقة العرض وحدها: لا عقود "
    "ولا خادم ولا قاعدة بيانات. «التوقعات» لا تزال تعرض المعرّف لأن "
    "FixturePredictionDto بلا display_name — إصلاحها يمسّ الخادم والعقود "
    "— apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart\n",
    encoding="utf-8",
)

run("git add apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart docs/checkpoints/session-log.md")
run('git commit -m "fix(admin): show participant display name in fixture report"')
print("✓ تم — بلا push")
