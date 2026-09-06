#!/usr/bin/env python3
"""23_fix_drawer_test_last_tile.

Second test in the same file also targeted a removed section: the mobile
drawer test tapped `settings`, chosen because it was the last tile (18/18)
and so exercised the lazy-ListView scroll path. `audit` is now last (8/8)
and plays the same role.
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

OLD = """        // "settings" هو العنصر الأخير (18/18) — لا يُبنى داخل شجرة الـListView
        // الكسول إلا بعد التمرير الفعلي إليه؛ ensureVisible لا يكفي لأنه
        // يتطلب أن يكون العنصر مبنيًا مسبقًا. scrollUntilVisible يُمرِّر
        // تدريجيًا حتى يظهر العنصر فعليًا في الشجرة.
        final Finder settingsTile = find.byKey(
          const Key('admin.shell.nav.settings'),
        );"""

NEW = """        // "audit" هو العنصر الأخير (8/8 بعد حذف الأقسام النائبة) — لا يُبنى
        // داخل شجرة الـListView الكسول إلا بعد التمرير الفعلي إليه؛
        // ensureVisible لا يكفي لأنه يتطلب أن يكون العنصر مبنيًا مسبقًا.
        // scrollUntilVisible يُمرِّر تدريجيًا حتى يظهر العنصر فعليًا.
        final Finder settingsTile = find.byKey(
          const Key('admin.shell.nav.audit'),
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
        + "\n2026-09-05 \u2014 22+23_drop_placeholder_admin_sections: "
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
        "\u0648\u062d\u064f\u0630\u0641 "
        "admin_coming_soon_section.dart\u060c "
        "\u0648\u062d\u064f\u0630\u0641\u062a \u0645\u062c\u0645\u0648\u0639\u0629 "
        "\u00ab\u0627\u0644\u0625\u062f\u0627\u0631\u0629\u00bb "
        "\u0644\u0641\u0642\u062f\u0627\u0646 \u0639\u0636\u0648\u064a\u0647\u0627\u060c "
        "\u0648\u0635\u0627\u0631\u062a \u0628\u0637\u0627\u0642\u0629 "
        "\u00ab\u0645\u0633\u0627\u0628\u0642\u0627\u062a "
        "\u0645\u062a\u0627\u062d\u0629\u00bb \u062a\u0634\u064a\u0631 \u0625\u0644\u0649 "
        "monthlyCompetitions \u0628\u062f\u0644 competitions "
        "\u0627\u0644\u0645\u062d\u0630\u0648\u0641. "
        "\u0627\u062e\u062a\u0628\u0627\u0631\u0627 admin_shell "
        "\u0643\u0627\u0646\u0627 \u064a\u0639\u062a\u0645\u062f\u0627\u0646 "
        "\u0639\u0644\u0649 \u0642\u0633\u0645\u064a\u0646 "
        "\u0645\u062d\u0630\u0648\u0641\u064a\u0646: teams "
        "(\u0644\u0644\u062a\u062d\u0642\u0651\u0642 \u0645\u0646 "
        "\u0627\u0644\u0646\u0627\u0626\u0628) \u0648settings "
        "(\u0644\u0623\u0646\u0647 \u0627\u0644\u0639\u0646\u0635\u0631 "
        "\u0627\u0644\u0623\u062e\u064a\u0631 \u0641\u064a "
        "\u0627\u0644\u0642\u0627\u0626\u0645\u0629 "
        "\u0627\u0644\u0643\u0633\u0648\u0644\u0629)\u061b "
        "\u0635\u0627\u0631\u0627 ledger \u0648audit "
        "\u0639\u0644\u0649 \u0627\u0644\u062a\u0631\u062a\u064a\u0628 "
        "\u0648\u0627\u062d\u062a\u0641\u0638\u0627 \u0628\u0646\u0641\u0633 "
        "\u0627\u0644\u062f\u0648\u0631. \u0645\u0624\u062c\u0651\u0644: "
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
