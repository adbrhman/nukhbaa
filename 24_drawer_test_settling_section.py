#!/usr/bin/env python3
"""24_drawer_test_settling_section.

pumpAndSettle after tapping `audit` never settles: AuditLogSection loads
on mount and its provider never completes in the test host, so a spinner
animates forever. The old target `settings` was an inert placeholder, so
this never came up.

`ledger` is the section the sibling desktop test already taps and settles
on, and at 6/8 it still sits below the fold in a 400x800 drawer, so the
lazy-ListView scroll path this test exists to cover is still exercised.
"""
import subprocess
import sys
from pathlib import Path

DRY = "--dry" in sys.argv

ROOT = Path.home() / "nukhbaa-backup-1787537565"
assert ROOT.is_dir(), f"missing project root: {ROOT}"

REL = "apps/mobile/test/features/admin/admin_shell_test.dart"
p = ROOT / REL
assert p.is_file(), f"missing file: {p}"
src = p.read_text(encoding="utf-8")

OLD = """        // "audit" هو العنصر الأخير (8/8 بعد حذف الأقسام النائبة) — لا يُبنى
        // داخل شجرة الـListView الكسول إلا بعد التمرير الفعلي إليه؛
        // ensureVisible لا يكفي لأنه يتطلب أن يكون العنصر مبنيًا مسبقًا.
        // scrollUntilVisible يُمرِّر تدريجيًا حتى يظهر العنصر فعليًا.
        final Finder settingsTile = find.byKey(
          const Key('admin.shell.nav.audit'),
        );"""

NEW = """        // "ledger" (6/8 بعد حذف الأقسام النائبة) دون الطيّ في شاشة 400×800،
        // فلا يُبنى داخل شجرة الـListView الكسول إلا بعد التمرير الفعلي
        // إليه؛ ensureVisible لا يكفي لأنه يتطلب أن يكون العنصر مبنيًا
        // مسبقًا. scrollUntilVisible يُمرِّر تدريجيًا حتى يظهر فعليًا.
        //
        // ليس "audit" (الأخير) لأن AuditLogSection يحمّل عند البناء ولا
        // يكتمل مزوّده في مضيف الاختبار، فيدور مؤشّره أبدًا ولا تستقرّ
        // pumpAndSettle بعد النقر. القسم النائب القديم كان خاملاً فلم
        // تظهر المسألة.
        final Finder settingsTile = find.byKey(
          const Key('admin.shell.nav.ledger'),
        );"""

n = src.count(OLD)
assert n == 1, f"anchor matched {n} times"
p.write_text(src.replace(OLD, NEW), encoding="utf-8")
print(f"ok {REL}")


def run(cmd, cwd=ROOT):
    print(f"$ {cmd}")
    if DRY:
        return
    r = subprocess.run(cmd, shell=True, cwd=cwd)
    if r.returncode != 0:
        sys.exit(r.returncode)


run(f"dart format {REL}")
run("cd apps/mobile && flutter analyze --no-fatal-infos lib/features/admin")
run("cd apps/mobile && flutter test --reporter=failures-only")

if not DRY:
    LOG = ROOT / "docs/checkpoints/session-log.md"
    LOG.write_text(
        LOG.read_text(encoding="utf-8")
        + "\n2026-09-05 \u2014 22..24_drop_placeholder_admin_sections: "
        "\u062d\u064f\u0630\u0641\u062a \u0639\u0634\u0631\u0629 "
        "\u0623\u0642\u0633\u0627\u0645 \u0646\u0627\u0626\u0628\u0629 "
        "\u0643\u0627\u0646\u062a \u062a\u0639\u0631\u0636 \u00ab\u0642\u064a\u062f "
        "\u0627\u0644\u062a\u0637\u0648\u064a\u0631\u00bb "
        "(dailyDoubles, leaderboards, competitions, teams, social, "
        "notifications, reportsAnalytics, systemHealth, rolesPermissions, "
        "settings)\u060c \u0641\u0628\u0642\u064a\u062a "
        "\u0627\u0644\u062b\u0645\u0627\u0646\u064a\u0629 "
        "\u0627\u0644\u0645\u0646\u0641\u064e\u0651\u0630\u0629. switch "
        "\u0641\u064a _bodyFor \u0635\u0627\u0631 "
        "\u0634\u0627\u0645\u0644\u064b\u0627 \u0641\u062d\u064f\u0630\u0641 "
        "\u0641\u0631\u0639 `_` \u0648\u0645\u0639\u0647 \u0645\u0639\u0627\u0645\u0644 "
        "l10n \u0648\u0645\u062a\u063a\u064a\u0651\u0631\u0647\u060c "
        "\u0648\u062d\u064f\u0630\u0641 admin_coming_soon_section.dart\u060c "
        "\u0648\u062d\u064f\u0630\u0641\u062a \u0645\u062c\u0645\u0648\u0639\u0629 "
        "\u00ab\u0627\u0644\u0625\u062f\u0627\u0631\u0629\u00bb\u060c "
        "\u0648\u0635\u0627\u0631\u062a \u0628\u0637\u0627\u0642\u0629 "
        "\u00ab\u0645\u0633\u0627\u0628\u0642\u0627\u062a "
        "\u0645\u062a\u0627\u062d\u0629\u00bb \u062a\u0634\u064a\u0631 \u0625\u0644\u0649 "
        "monthlyCompetitions. \u0627\u062e\u062a\u0628\u0627\u0631\u0627 "
        "admin_shell \u0643\u0627\u0646\u0627 "
        "\u064a\u0639\u062a\u0645\u062f\u0627\u0646 \u0639\u0644\u0649 "
        "teams \u0648settings \u0627\u0644\u0645\u062d\u0630\u0648\u0641\u064a\u0646\u061b "
        "\u0635\u0627\u0631\u0627 \u064a\u0633\u062a\u062e\u062f\u0645\u0627\u0646 "
        "ledger. \u062f\u0631\u0633 \u0645\u0633\u062a\u0641\u0627\u062f: "
        "\u0627\u0633\u062a\u0628\u062f\u0627\u0644 \u0642\u0633\u0645 "
        "\u0646\u0627\u0626\u0628 \u062e\u0627\u0645\u0644 \u0628\u0642\u0633\u0645 "
        "\u062d\u0642\u064a\u0642\u064a \u0641\u064a "
        "\u0627\u062e\u062a\u0628\u0627\u0631 \u0644\u064a\u0633 "
        "\u0645\u062d\u0627\u064a\u062f\u064b\u0627 \u2014 audit "
        "\u064a\u062d\u0645\u0651\u0644 \u0639\u0646\u062f "
        "\u0627\u0644\u0628\u0646\u0627\u0621 \u0648\u0644\u0627 "
        "\u064a\u0643\u062a\u0645\u0644 \u0645\u0632\u0648\u0651\u062f\u0647 "
        "\u0641\u064a \u0645\u0636\u064a\u0641 "
        "\u0627\u0644\u0627\u062e\u062a\u0628\u0627\u0631\u060c "
        "\u0641\u062a\u0646\u062a\u0647\u064a \u0645\u0647\u0644\u0629 "
        "pumpAndSettle. \u0645\u0624\u062c\u0651\u0644: "
        "\u0645\u0641\u0627\u062a\u064a\u062d ARB "
        "\u0627\u0644\u064a\u062a\u064a\u0645\u0629 "
        "(adminTeamsTab \u0648\u0625\u062e\u0648\u0627\u062a\u0647\u0627 "
        "\u0648adminSectionComingSoon) \u2014 "
        "\u062f\u0641\u0639\u0629 \u0645\u0633\u062a\u0642\u0644\u0629 "
        "\u0639\u0644\u0649 \u0646\u0645\u0637 17_remove_orphan_l10n_keys "
        "\u2014 apps/mobile/lib/features/admin/admin_sections.dart, "
        "apps/mobile/lib/features/admin/admin_shell.dart, "
        "apps/mobile/lib/features/admin/screens/sections/admin_dashboard_section.dart, "
        "apps/mobile/test/features/admin/admin_shell_test.dart, "
        "(deleted) apps/mobile/lib/features/admin/screens/sections/admin_coming_soon_section.dart\n",
        encoding="utf-8",
    )

run("git add apps/mobile/lib/features/admin/admin_sections.dart "
    "apps/mobile/lib/features/admin/admin_shell.dart "
    "apps/mobile/lib/features/admin/screens/sections/admin_dashboard_section.dart "
    "apps/mobile/test/features/admin/admin_shell_test.dart "
    "docs/checkpoints/session-log.md")
run('git commit -m "refactor(admin): drop ten placeholder sections and their coming-soon view"')
print("done - no push")
