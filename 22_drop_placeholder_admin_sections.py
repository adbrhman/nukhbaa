#!/usr/bin/env python3
"""22_drop_placeholder_admin_sections.

Ten AdminSection values had no implementation and fell through to
AdminComingSoonSection. Removing the values makes the _bodyFor switch
exhaustive, so the `_ =>` arm goes too (an unreachable default is a
warning under --fatal-warnings).

Kept: dashboard, monthlyCompetitions, fixtures, predictions,
resultsScoring, users, ledger, audit -- the eight with real sections.

Side effects handled here:
- the dashboard's "competitions available" card pointed at a removed
  section; repointed at monthlyCompetitions, which is where monthly
  competitions are actually managed.
- the "administration" nav group loses both its members, so the group
  itself goes.
- the shell widget test navigated to `teams` to assert the coming-soon
  placeholder; it now navigates to `ledger` (still the far end of the
  nav list, so the scroll path is still exercised) and asserts the real
  section.

NOT done here: the orphaned ARB keys (adminTeamsTab, ...,
adminSectionComingSoon). Separate pass, like 17_remove_orphan_l10n_keys.
"""
import subprocess
import sys
from pathlib import Path

DRY = "--dry" in sys.argv

ROOT = Path.home() / "nukhbaa-backup-1787537565"
assert ROOT.is_dir(), f"missing project root: {ROOT}"


def patch(rel, pairs):
    p = ROOT / rel
    assert p.is_file(), f"missing file: {p}"
    src = p.read_text(encoding="utf-8")
    for i, (old, new) in enumerate(pairs):
        n = src.count(old)
        assert n == 1, f"{rel}: anchor #{i} matched {n} times"
        src = src.replace(old, new)
    p.write_text(src, encoding="utf-8")
    print(f"ok {rel}")


# ----------------------------------------------------------------- the enum
patch(
    "apps/mobile/lib/features/admin/admin_sections.dart",
    [
        (
            """/// كل قسم من أقسام لوحة تحكم الأدمن. القائمة مطابقة للهيكل المعتمد
/// (راجع قسم 9 من مرجع الاستمرارية). الأقسام التي لا تملك تنفيذاً فعلياً
/// بعد تعرض [AdminComingSoonSection] عبر [AdminShell._bodyFor].
///
/// ملاحظة: `ledger` (البحث في السجل المالي) محفوظة رغم غيابها عن الهيكل
/// المطلوب — ميزة حقيقية قائمة، لا تُحذف دون موافقة صريحة.
enum AdminSection {
  dashboard(icon: Icons.dashboard_rounded),
  monthlyCompetitions(icon: Icons.calendar_month_rounded),
  fixtures(icon: Icons.sports_soccer_rounded),
  predictions(icon: Icons.rule_folder_rounded),
  dailyDoubles(icon: Icons.bolt_rounded),
  resultsScoring(icon: Icons.scoreboard_rounded),
  leaderboards(icon: Icons.leaderboard_rounded),
  users(icon: Icons.people_alt_rounded),
  competitions(icon: Icons.emoji_events_rounded),
  teams(icon: Icons.groups_rounded),
  social(icon: Icons.forum_rounded),
  notifications(icon: Icons.notifications_rounded),
  reportsAnalytics(icon: Icons.insights_rounded),
  ledger(icon: Icons.account_balance_wallet_rounded),
  audit(icon: Icons.receipt_long_rounded),
  systemHealth(icon: Icons.health_and_safety_rounded),
  rolesPermissions(icon: Icons.admin_panel_settings_rounded),
  settings(icon: Icons.settings_rounded);""",
            """/// كل قسم من أقسام لوحة تحكم الأدمن. القائمة تحوي الأقسام المنفَّذة فقط:
/// عشرة أقسام نائبة كانت تعرض «قيد التطوير» حُذفت بقرار صريح، فلا تظهر في
/// التنقّل ما لا يعمل. إعادة أي منها تعني إعادة قيمته هنا مع قسمه الفعلي.
///
/// ملاحظة: `ledger` (البحث في السجل المالي) محفوظة رغم غيابها عن الهيكل
/// المطلوب — ميزة حقيقية قائمة، لا تُحذف دون موافقة صريحة.
enum AdminSection {
  dashboard(icon: Icons.dashboard_rounded),
  monthlyCompetitions(icon: Icons.calendar_month_rounded),
  fixtures(icon: Icons.sports_soccer_rounded),
  predictions(icon: Icons.rule_folder_rounded),
  resultsScoring(icon: Icons.scoreboard_rounded),
  users(icon: Icons.people_alt_rounded),
  ledger(icon: Icons.account_balance_wallet_rounded),
  audit(icon: Icons.receipt_long_rounded);""",
        )
    ],
)

# ---------------------------------------------------------------- the shell
patch(
    "apps/mobile/lib/features/admin/admin_shell.dart",
    [
        (
            """    AdminSection.predictions => l10n.adminPredictionsTab,
    AdminSection.dailyDoubles => l10n.adminDailyDoublesTab,
    AdminSection.resultsScoring => l10n.adminResultsScoringTab,
    AdminSection.leaderboards => l10n.adminLeaderboardsTab,
    AdminSection.users => l10n.adminUsersTab,
    AdminSection.competitions => l10n.adminCompetitionsTab,
    AdminSection.teams => l10n.adminTeamsTab,
    AdminSection.social => l10n.adminSocialTab,
    AdminSection.notifications => l10n.adminNotificationsTab,
    AdminSection.reportsAnalytics => l10n.adminReportsAnalyticsTab,
    AdminSection.ledger => l10n.adminLedgerLookupTab,
    AdminSection.audit => l10n.adminAuditLogTab,
    AdminSection.systemHealth => l10n.adminSystemHealthTab,
    AdminSection.rolesPermissions => l10n.adminRolesPermissionsTab,
    AdminSection.settings => l10n.adminSettingsTab,""",
            """    AdminSection.predictions => l10n.adminPredictionsTab,
    AdminSection.resultsScoring => l10n.adminResultsScoringTab,
    AdminSection.users => l10n.adminUsersTab,
    AdminSection.ledger => l10n.adminLedgerLookupTab,
    AdminSection.audit => l10n.adminAuditLogTab,""",
        ),
        (
            """  (
    title: 'المسابقات والمباريات',
    sections: [
      AdminSection.monthlyCompetitions,
      AdminSection.competitions,
      AdminSection.fixtures,
      AdminSection.predictions,
      AdminSection.resultsScoring,
      AdminSection.dailyDoubles,
    ],
  ),
  (
    title: 'النقاط والترتيب',
    sections: [AdminSection.leaderboards, AdminSection.ledger],
  ),
  (
    title: 'المستخدمون والتفاعل',
    sections: [
      AdminSection.users,
      AdminSection.teams,
      AdminSection.social,
      AdminSection.notifications,
    ],
  ),
  (
    title: 'التحليلات والأمان',
    sections: [
      AdminSection.reportsAnalytics,
      AdminSection.audit,
      AdminSection.systemHealth,
    ],
  ),
  (
    title: 'الإدارة',
    sections: [AdminSection.rolesPermissions, AdminSection.settings],
  ),
];""",
            """  (
    title: 'المسابقات والمباريات',
    sections: [
      AdminSection.monthlyCompetitions,
      AdminSection.fixtures,
      AdminSection.predictions,
      AdminSection.resultsScoring,
    ],
  ),
  (title: 'النقاط والترتيب', sections: [AdminSection.ledger]),
  (title: 'المستخدمون والتفاعل', sections: [AdminSection.users]),
  (title: 'التحليلات والأمان', sections: [AdminSection.audit]),
];""",
        ),
        (
            """  Widget _bodyFor(AdminSection section, AppLocalizations l10n) {""",
            """  Widget _bodyFor(AdminSection section) {""",
        ),
        (
            """      AdminSection.predictions => const AdminPredictionsSection(),
      _ => AdminComingSoonSection(title: adminSectionLabel(section, l10n)),
    };""",
            """      AdminSection.predictions => const AdminPredictionsSection(),
    };""",
        ),
        # The label lookup was the only reader of l10n in this build method;
        # keeping the local would be an unused-variable warning.
        (
            """    final AppLocalizations l10n = AppLocalizations.of(context);
    final AppTokens t = context.tokens;
    final bool isMobile = AppBreakpoints.isMobile(context);

    final Widget body = Padding(
      key: const Key('admin.shell.body'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _bodyFor(selected, l10n),
    );""",
            """    final AppTokens t = context.tokens;
    final bool isMobile = AppBreakpoints.isMobile(context);

    final Widget body = Padding(
      key: const Key('admin.shell.body'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _bodyFor(selected),
    );""",
        ),
    ],
)

# -------------------------------------------------------------- the dashboard
patch(
    "apps/mobile/lib/features/admin/screens/sections/admin_dashboard_section.dart",
    [
        (
            """        section: AdminSection.competitions,""",
            """        section: AdminSection.monthlyCompetitions,""",
        )
    ],
)

# ------------------------------------------------------------- the shell test
patch(
    "apps/mobile/test/features/admin/admin_shell_test.dart",
    [
        (
            """        final Finder teamsTile = find.byKey(const Key('admin.shell.nav.teams'));""",
            """        final Finder teamsTile = find.byKey(
          const Key('admin.shell.nav.ledger'),
        );""",
        ),
        (
            """        expect(find.text(l10n.adminTeamsTab), findsWidgets);
        expect(find.text(l10n.adminSectionComingSoon), findsOneWidget);""",
            """        expect(find.text(l10n.adminLedgerLookupTab), findsWidgets);""",
        ),
    ],
)


def run(cmd, cwd=ROOT):
    print(f"$ {cmd}")
    if DRY:
        return
    r = subprocess.run(cmd, shell=True, cwd=cwd)
    if r.returncode != 0:
        sys.exit(r.returncode)


DEAD = ROOT / "apps/mobile/lib/features/admin/screens/sections/admin_coming_soon_section.dart"
if not DRY:
    run("git rm -q apps/mobile/lib/features/admin/screens/sections/admin_coming_soon_section.dart")
else:
    assert DEAD.is_file(), "coming-soon section already gone"

# The import of the deleted file is dropped by a targeted edit, not a
# blanket regex: only the shell imported it.
SHELL = ROOT / "apps/mobile/lib/features/admin/admin_shell.dart"
shell_src = SHELL.read_text(encoding="utf-8")
imports = [
    line
    for line in shell_src.splitlines(keepends=True)
    if "admin_coming_soon_section.dart" in line
]
assert len(imports) == 1, f"expected 1 import line, found {len(imports)}"
SHELL.write_text(shell_src.replace(imports[0], ""), encoding="utf-8")
print("ok dropped the coming-soon import")

run("dart format apps/mobile/lib/features/admin apps/mobile/test/features/admin")
run("cd apps/mobile && flutter analyze --no-fatal-infos lib/features/admin")
run("cd apps/mobile && flutter test --reporter=failures-only")

if not DRY:
    LOG = ROOT / "docs/checkpoints/session-log.md"
    LOG.write_text(
        LOG.read_text(encoding="utf-8")
        + "\n2026-09-05 \u2014 22_drop_placeholder_admin_sections: "
        "\u062d\u064f\u0630\u0641\u062a \u0639\u0634\u0631\u0629 "
        "\u0623\u0642\u0633\u0627\u0645 \u0646\u0627\u0626\u0628\u0629 "
        "\u0643\u0627\u0646\u062a \u062a\u0639\u0631\u0636 \u00ab\u0642\u064a\u062f "
        "\u0627\u0644\u062a\u0637\u0648\u064a\u0631\u00bb "
        "(dailyDoubles, leaderboards, competitions, teams, social, "
        "notifications, reportsAnalytics, systemHealth, rolesPermissions, "
        "settings)\u060c \u0641\u0628\u0642\u064a\u062a "
        "\u0627\u0644\u062b\u0645\u0627\u0646\u064a\u0629 "
        "\u0627\u0644\u0645\u0646\u0641\u064e\u0651\u0630\u0629. \u0635\u0627\u0631 "
        "switch \u0641\u064a _bodyFor \u0634\u0627\u0645\u0644\u064b\u0627 "
        "\u0641\u062d\u064f\u0630\u0641 \u0641\u0631\u0639 `_` "
        "(\u0627\u0641\u062a\u0631\u0627\u0636\u064a "
        "\u063a\u064a\u0631 \u0642\u0627\u0628\u0644 "
        "\u0644\u0644\u0648\u0635\u0648\u0644 = \u062a\u062d\u0630\u064a\u0631 "
        "\u062a\u062d\u062a --fatal-warnings)\u060c "
        "\u0648\u062d\u064f\u0630\u0641 "
        "admin_coming_soon_section.dart. "
        "\u0645\u062c\u0645\u0648\u0639\u0629 \u00ab\u0627\u0644\u0625\u062f\u0627\u0631\u0629\u00bb "
        "\u0641\u0642\u062f\u062a \u0639\u0636\u0648\u064a\u0647\u0627 "
        "\u0641\u062d\u064f\u0630\u0641\u062a. \u0628\u0637\u0627\u0642\u0629 "
        "\u00ab\u0645\u0633\u0627\u0628\u0642\u0627\u062a "
        "\u0645\u062a\u0627\u062d\u0629\u00bb \u0641\u064a \u0644\u0648\u062d\u0629 "
        "\u0627\u0644\u0645\u0639\u0644\u0648\u0645\u0627\u062a "
        "\u0643\u0627\u0646\u062a \u062a\u0634\u064a\u0631 \u0625\u0644\u0649 "
        "competitions \u0627\u0644\u0645\u062d\u0630\u0648\u0641 "
        "\u0641\u0635\u0627\u0631\u062a \u0625\u0644\u0649 "
        "monthlyCompetitions. \u0627\u062e\u062a\u0628\u0627\u0631 "
        "admin_shell \u0643\u0627\u0646 \u064a\u0646\u062a\u0642\u0644 "
        "\u0625\u0644\u0649 teams \u0644\u064a\u062a\u062d\u0642\u0651\u0642 "
        "\u0645\u0646 \u0627\u0644\u0646\u0627\u0626\u0628\u061b \u0635\u0627\u0631 "
        "\u064a\u0646\u062a\u0642\u0644 \u0625\u0644\u0649 ledger "
        "(\u0645\u0627 \u064a\u0632\u0627\u0644 \u0641\u064a "
        "\u0637\u0631\u0641 \u0627\u0644\u0642\u0627\u0626\u0645\u0629 "
        "\u0641\u064a\u064f\u062e\u062a\u0628\u0631 "
        "\u0627\u0644\u062a\u0645\u0631\u064a\u0631). "
        "\u0645\u0624\u062c\u0651\u0644: "
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
