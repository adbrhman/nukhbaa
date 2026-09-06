#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""13 — «توقعاتي» تعرض أسماء الفرق وشعاراتها بدل المعرّف الخام.

السبب: _FixturePredictionCard يمرّر `fixture: null` صراحةً، فيسقط
_ScoreLine إلى فرعه الاحتياطي الذي يطبع fixtureId. الودجت التي ترسم
الشعارين والاسمين والعلامة (✅/❌/🔥) موجودة وسليمة — تنتظر بيانات
لا تصلها.

الحل بلا تعديل عقود: FixturePredictionDto يحمل seasonId، وseasonFixturesProvider
يعيد SeasonFixtureCardDto وفيه homeTeam/awayTeam. فالبطاقة تشاهده وتبحث
عن fixtureId. يعمل لكل التاريخ لا للشهر الجاري فقط، لأن المفتاح هو موسم
التوقّع نفسه.

_ScoreLine كان يتوقّع RoundFixtureCardDto من نموذج الجولات المُسقَط؛ صار
يقبل SeasonFixtureCardDto — الحقلان بنفس الاسم فالتغيير سطحي.

و_TeamMini كان يقرأ brand?.logoUrl (شبكة ESPN) وحده؛ صار يمرّر assetPath
من resolveTeamIdentity فيظهر الشعار المرفق محلّيًا أولًا، كما في بطاقة
المباراة.

التدهور يبقى آمنًا: seasonId فارغ، أو قراءة قيد التحميل، أو مباراة غير
موجودة — كلها تعود إلى نفس الفرع الاحتياطي، لا بطاقة مكسورة.
"""
import datetime
import io
import os
import subprocess
import sys

REL = "apps/mobile/lib/features/history/prediction_history_screen.dart"

EDITS = [
    # 1) استيراد المزوّد ومُحلِّل الهوية.
    (
        """import '../competition/team_registry.dart';
import '../competition/widgets/async_list_view.dart';
import 'fixture_scores_providers.dart';""",
        """import '../competition/team_identity.dart';
import '../competition/widgets/async_list_view.dart';
import '../fixture_prediction/fixture_prediction_providers.dart';
import 'fixture_scores_providers.dart';""",
    ),
    # 2) حلّ المباراة من مواسم التوقّع بدل تمرير null.
    (
        """    String? grade;
    for (final ParticipantFixtureScoreDto s
        in scoresAsync?.value?.scores ?? const []) {
      if (s.participantId == prediction.participantId) {
        grade = s.grade;
        break;
      }
    }""",
        """    String? grade;
    for (final ParticipantFixtureScoreDto s
        in scoresAsync?.value?.scores ?? const []) {
      if (s.participantId == prediction.participantId) {
        grade = s.grade;
        break;
      }
    }

    // The prediction carries its season, and the season's fixture list
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
    ),
    (
        """                fixture: null,""",
        """                fixture: fixture,""",
    ),
    # 3) النوع المتوقَّع صار من نموذج المباريات.
    (
        """  final FixtureScoreDto score;
  final RoundFixtureCardDto? fixture;
  final String? grade;""",
        """  final FixtureScoreDto score;
  final SeasonFixtureCardDto? fixture;
  final String? grade;""",
    ),
    (
        """    final RoundFixtureCardDto? f = fixture;""",
        """    final SeasonFixtureCardDto? f = fixture;""",
    ),
    # 4) الشعار المرفق محلّيًا يسبق الشبكة، كما في بطاقة المباراة.
    (
        """    final AppTokens tokens = context.tokens;
    final TeamBrand? brand = lookupTeam(name);
    final String display = teamDisplayName(name);
    final Widget crest = TeamLogo(
      displayName: display,
      crestUrl: brand?.logoUrl,
      brandColor: brand?.c1,
      size: _crestSize,
    );""",
        """    final AppTokens tokens = context.tokens;
    final ResolvedTeamIdentity identity = resolveTeamIdentity(teamName: name);
    final String display = identity.displayName;
    final Widget crest = TeamLogo(
      displayName: display,
      crestUrl: identity.crestUrl,
      assetPath: identity.assetPath,
      brandColor: identity.brandColor,
      size: _crestSize,
    );""",
    ),
    # 5) التعليق الوصفي صار مضلّلًا.
    (
        """/// There is no season/round context to resolve team names from here —
/// [FixturePredictionDto] carries only the fixture id — so the score line
/// always falls back to the raw fixture id (the same fallback [_ScoreLine]
/// renders whenever it isn't given a resolved [RoundFixtureCardDto]). The""",
        """/// Team names come from [seasonFixturesProvider], keyed by the prediction's
/// own [FixturePredictionDto.seasonId], so every season the caller ever
/// played resolves — not just the current month. A null seasonId, a
/// still-loading read, or a fixture no longer linked to the season all fall
/// back to the raw fixture id rather than a broken card. The""",
    ),
    (
        """/// One fixture's scoreline: "[crest] Home  2 - 1  Away [crest]". Falls back to
/// the raw fixture id (no crests) when [fixture] is `null` — the resolved read
/// hasn't returned this fixture yet, or it is no longer linked to the round.""",
        """/// One fixture's scoreline: "[crest] Home  2 - 1  Away [crest]". Falls back to
/// the raw fixture id (no crests) when [fixture] is `null` — the resolved read
/// hasn't returned this fixture yet, or it is no longer linked to the season.""",
    ),
]

LOG = (
    "13_history_team_names: شاشة «توقعاتي» كانت تعرض fixtureId الخام لأن "
    "_FixturePredictionCard يمرّر `fixture: null` صراحةً، فيسقط _ScoreLine "
    "إلى فرعه الاحتياطي رغم أن ودجت الشعارين والاسمين والعلامة موجودة "
    "وسليمة؛ صارت البطاقة تشاهد seasonFixturesProvider(seasonId) وتبحث عن "
    "fixtureId فيه (يعمل لكل المواسم لا الشهر الجاري)، وتحوّل _ScoreLine من "
    "RoundFixtureCardDto المُسقَط إلى SeasonFixtureCardDto، ويمرّر _TeamMini "
    "assetPath من resolveTeamIdentity فيسبق الشعار المرفق شبكة ESPN. بلا "
    "تعديل عقود ولا خادم — %s" % REL
)
MSG = "fix(mobile): resolve team names and crests in the prediction history"


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
            sys.exit("[!] 13.%d: المرساة غير موجودة أو متكررة في %s" % (i, REL))
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
    print("[ok] 13 done")


main()
