#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""34_leaderboards_single_month — تبويب واحد: الموسم الذي فيه مباريات فعلًا."""
import os, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
M = os.path.join(ROOT, "apps/mobile")
assert os.path.isdir(M), "apps/mobile not found under %s" % ROOT

REL = "lib/features/leaderboards/leaderboards_screen.dart"
P = os.path.join(M, REL)
with open(P, encoding="utf-8") as f:
    s = f.read()


def rep(old, new):
    global s
    assert s.count(old) == 1, "anchor x%d in %s" % (s.count(old), REL)
    s = s.replace(old, new, 1)


rep(
    """import '../competition/competition_providers.dart';
import '../competition/widgets/async_list_view.dart';
import 'leaderboards_providers.dart';""",
    """import '../competition/competition_providers.dart';
import '../competition/widgets/async_list_view.dart';
import '../fixture_prediction/current_month_fixtures_providers.dart';
import 'leaderboards_providers.dart';""",
)

rep(
    """/// Discovery entry point for leaderboards. It uses the caller's active seasons
/// as the server-backed scope and reuses the same season leaderboard provider
/// as the contextual board opened from a fixture.""",
    """/// Discovery entry point for leaderboards. It uses the caller's active seasons
/// as the server-backed scope and reuses the same season leaderboard provider
/// as the contextual board opened from a fixture.
///
/// ## One board, not one per league
/// The contest is the calendar month, not the league: the admin files
/// fixtures from several leagues into the month's competition, every user
/// predicts all of them together, and the month's highest total wins. A
/// league is only a source of fixtures, so a per-league tab is not a view
/// of anything — and in practice the account carries memberships in league
/// seasons that hold **zero** fixtures, which rendered as tabs onto empty
/// boards.
///
/// So the tabs are narrowed to the seasons that actually carry a fixture
/// this month, read off [currentMonthFixturesProvider] — the same feed the
/// matches screen already watches, so this costs no new endpoint, no new
/// provider and no server change. It is also self-maintaining: next
/// month's season appears the moment it has a fixture, and an emptied
/// season drops out on its own.
///
/// Deliberately a **view** narrowing, not a data deletion: the league
/// seasons and their memberships stay in the database untouched (project
/// owner's choice — option ب). If they are ever removed for real, this
/// filter becomes a no-op rather than a thing to undo.
///
/// If the fixtures feed has not resolved (or failed), the filter is skipped
/// entirely and every active season is shown — a leaderboard must not go
/// blank because an unrelated read is in flight.""",
)

rep(
    """        data: (items) {
          if (items.isEmpty) {""",
    """        data: (items) {
          final Set<String>? seasonsWithFixtures = monthFixtures.hasValue
              ? monthFixtures.value!
                    .map((item) => item.fixture.seasonId)
                    .toSet()
              : null;
          final List<ActiveSeasonDto> visible = seasonsWithFixtures == null
              ? items
              : items
                    .where(
                      (season) =>
                          seasonsWithFixtures.contains(season.seasonId),
                    )
                    .toList(growable: false);
          if (visible.isEmpty) {""",
)

rep(
    """          return DefaultTabController(
            length: items.length,
            child: Column(
              children: <Widget>[
                TabBar(
                  isScrollable: true,
                  tabs: items
                      .map(
                        (season) => Tab(
                          key: Key('leaderboards.season.${season.seasonId}'),
                          text:
                              '${season.competitionName} · ${season.seasonLabel}',
                        ),
                      )
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: items
                        .map(
                          (season) =>
                              _SeasonLeaderboard(seasonId: season.seasonId),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );""",
    """          // A single-tab TabBar is chrome around nothing — the expected
          // steady state now that the month is the competition.
          if (visible.length == 1) {
            return _SeasonLeaderboard(seasonId: visible.first.seasonId);
          }
          return DefaultTabController(
            length: visible.length,
            child: Column(
              children: <Widget>[
                TabBar(
                  isScrollable: true,
                  tabs: visible
                      .map(
                        (season) => Tab(
                          key: Key('leaderboards.season.${season.seasonId}'),
                          text:
                              '${season.competitionName} · ${season.seasonLabel}',
                        ),
                      )
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: visible
                        .map(
                          (season) =>
                              _SeasonLeaderboard(seasonId: season.seasonId),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );""",
)

rep(
    "    final seasons = ref.watch(activeSeasonsProvider);",
    "    final seasons = ref.watch(activeSeasonsProvider);\n"
    "    final monthFixtures = ref.watch(currentMonthFixturesProvider);",
)

with open(P, "w", encoding="utf-8") as f:
    f.write(s)
print("patched", REL)

subprocess.run(["dart", "format", os.path.join(M, REL)], check=True)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 34_leaderboards_single_month: «المتصدرون» كانت تعرض "
    "تبويبًا لكل موسم يشارك فيه المستخدم، فظهرت تبويبات «الدوري الألماني "
    "2026/27» و«الدوري الإسباني» على لوحات فارغة. الفحص على قاعدة الإنتاج "
    "بيّن السبب: تسع مسابقات، واحدة فقط («شهر 9» / 09/2026) فيها مباريات "
    "(21)، والثماني الباقية بصفر مباراة ومعها 182 اشتراكًا — بقايا نموذج "
    "الدوريات قبل التحوّل إلى «الشهر هو المسابقة». الدفتر كلّه (8 قيود) في "
    "«شهر 9» وحدها. فالتبويبات صارت مقصورة على المواسم التي تحمل مباراة "
    "فعلًا، مقروءة من currentMonthFixturesProvider نفسه الذي تشاهده شاشة "
    "المباريات: لا مسار ولا مزوّد ولا تغيير خادم، ويصحّح نفسه شهريًا. "
    "وموسم واحد يعني لا شريط تبويبات أصلًا. اختير التضييق في العرض على "
    "الحذف (الخيار ب بقرار المالك): زناد ledger.reject_entry_mutation "
    "يمنع حذف الدفتر، وخمسة عشر قيد RESTRICT عبر خمسة schemas تجعل الحذف "
    "عملية من عشر عبارات على بيانات مستخدمين حقيقيين — والبيانات الميتة "
    "لا تؤذي. أُخذت نسخة pg_dump احتياطية قبل الفحص. إن حُذفت المواسم "
    "لاحقًا يصير هذا المرشّح بلا أثر بدل أن يكون شيئًا يُتراجع عنه. "
    "مؤجَّل: start_at لموسم «شهر 9» هو 2026-08-01 لا 2026-09-01، أي شهران "
    "خلافًا لقاعدة المسابقة — "
    "apps/mobile/lib/features/leaderboards/leaderboards_screen.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = [
    "apps/mobile/lib/features/leaderboards/leaderboards_screen.dart",
    "docs/checkpoints/session-log.md",
]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "fix(mobile): leaderboards show only seasons that carry fixtures"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
