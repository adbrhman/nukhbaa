#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""15 — «توقعاتي» عادت تعرض المعرّف بعد توحيد المسابقة الشهرية.

السبب: FixturePredictionDto.seasonId مشتقّ في الخادم من
participant_id -> competition.participants.season_id، أي أنه **موسم
المشارك** لا موسم المباراة. وبعد نقل كل مباريات سبتمبر إلى موسم «شهر 9»
بقي المشاركون في مواسم دورياتهم (147 في 2026/27، 35 في 2026/2027، 9 فقط
في 09/2026). فـseasonFixturesProvider(seasonId) يعيد قائمة فارغة، ولا
تُطابق أي مباراة، ويسقط _ScoreLine إلى فرعه الاحتياطي.

الحل: القراءة من currentMonthFixturesProvider بدلًا منه — وهو يعيد
مباريات الشهر الجاري أيًّا كان موسمها، وهو نفسه ما تعرضه شاشة المباريات.
لا لمس لقاعدة البيانات: توحيد المشاركين يمسّ مفتاحًا أجنبيًا في
fixture_predictions وfixture_scores وfixture_point_entries معًا، وهو
عمل جراحي لا رجعة فيه لأجل عرض نصّي.

قيده المقبول: توقعات الشهور الماضية تبقى بالمعرّف. ولا توجد شهور ماضية —
المسابقة بدأت هذا الشهر.

seasonId يبقى مستعملًا كما هو لقراءة fixtureScoresProvider (الدرجة
والعلامة)، فهذا المسار لا يتأثر.
"""
import datetime
import io
import os
import subprocess
import sys

REL = "apps/mobile/lib/features/history/prediction_history_screen.dart"

EDITS = [
    (
        """import '../fixture_prediction/fixture_prediction_providers.dart';""",
        """import '../fixture_prediction/current_month_fixtures_providers.dart';""",
    ),
    (
        """    // The prediction carries its season, and the season's fixture list
    // carries the team names — so the history resolves names for every
    // season the caller ever played, not just the current month.
    final AsyncValue<List<SeasonFixtureCardDto>>? fixturesAsync =
        seasonId == null ? null : ref.watch(seasonFixturesProvider(seasonId));
    SeasonFixtureCardDto? fixture;
    for (final SeasonFixtureCardDto f
        in fixturesAsync?.value ?? const <SeasonFixtureCardDto>[]) {
      if (f.fixtureId == prediction.fixtureId) {
        fixture = f;
        break;
      }
    }""",
        """    // Team names come from the current-month feed, not from the
    // prediction's own season: `seasonId` is derived server-side from the
    // *participant's* season, which is not where the fixtures live once a
    // monthly competition gathers fixtures from several leagues.
    final AsyncValue<List<CurrentMonthFixtureItemDto>> monthAsync = ref.watch(
      currentMonthFixturesProvider,
    );
    SeasonFixtureCardDto? fixture;
    for (final CurrentMonthFixtureItemDto item
        in monthAsync.value ?? const <CurrentMonthFixtureItemDto>[]) {
      if (item.fixture.fixtureId == prediction.fixtureId) {
        fixture = item.fixture;
        break;
      }
    }""",
    ),
    (
        """/// Team names come from [seasonFixturesProvider], keyed by the prediction's
/// own [FixturePredictionDto.seasonId], so every season the caller ever
/// played resolves — not just the current month. A null seasonId, a
/// still-loading read, or a fixture no longer linked to the season all fall
/// back to the raw fixture id rather than a broken card. The""",
        """/// Team names come from [currentMonthFixturesProvider] — the same feed the
/// fixtures screen renders — because [FixturePredictionDto.seasonId] is the
/// *participant's* season, not the fixture's, and a monthly competition
/// gathers its fixtures from several leagues. A still-loading read, or a
/// fixture outside the current month, falls back to the raw fixture id
/// rather than a broken card. The""",
    ),
]

LOG = (
    "15_history_from_month_feed: «توقعاتي» عادت تعرض المعرّف بعد نقل مباريات "
    "سبتمبر إلى موسم «شهر 9»، لأن FixturePredictionDto.seasonId هو موسم "
    "المشارك لا موسم المباراة (147 مشاركًا في 2026/27 مقابل 9 في 09/2026)، "
    "فيعيد seasonFixturesProvider قائمة فارغة؛ صارت القراءة من "
    "currentMonthFixturesProvider وهو نفس ما تعرضه شاشة المباريات. لم نوحّد "
    "المشاركين في قاعدة البيانات لأن participant_id مفتاح أجنبي في "
    "fixture_predictions وfixture_scores وfixture_point_entries — %s" % REL
)
MSG = "fix(mobile): resolve history fixtures from the current-month feed"


def main():
    root = os.path.abspath(os.environ.get("NUKHBAA_ROOT") or os.getcwd())
    if not os.path.isdir(os.path.join(root, "apps/mobile/lib")):
        sys.exit("[!] ليس جذر المشروع: %s — صدّر NUKHBAA_ROOT" % root)
    who = subprocess.run(["whoami"], capture_output=True, text=True).stdout.strip()
    print("[i] user=%s root=%s" % (who, root))

    path = os.path.join(root, REL)
    src = io.open(path, encoding="utf-8").read()
    for i, (old, new) in enumerate(EDITS, 1):
        if src.count(old) != 1:
            sys.exit("[!] 15.%d: المرساة غير موجودة أو متكررة في %s" % (i, REL))
        src = src.replace(old, new, 1)
    io.open(path, "w", encoding="utf-8").write(src)
    print("[ok] patched", REL)

    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with io.open(
        os.path.join(root, "docs/checkpoints/session-log.md"), "a", encoding="utf-8"
    ) as f:
        f.write("\n%s — %s\n" % (ts, LOG))

    subprocess.run(
        ["git", "add", REL, "docs/checkpoints/session-log.md"], cwd=root, check=True
    )
    subprocess.run(["git", "commit", "-m", MSG], cwd=root)
    print("[ok] 15 done")


main()
