#!/usr/bin/env python3
"""26_month_season_link_guard.

The structural hole behind the 423/32 split: ListCurrentMonthFixtures picks,
per competition, the season whose window covers now -- and a league season
("2026/27") covers September too. A fixture linked there is served to the
client under that season id, so the participant is created there and its
points never reach the monthly board.

The guard: a fixture may only be linked to a season whose [startAt, endAt)
window stays inside one calendar month. Self-contained -- no new column, no
migration, no schema change. Data is already consistent (17 fixtures, all
under 09/2026; league seasons hold none), so nothing existing is rejected.
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


patch(
    "packages/application/lib/src/competition/link_fixture_to_season.dart",
    [
        (
            """/// Unlike [LinkFixtureToRound] there is no lifecycle status to gate against
/// (a season carries none) â€” the only precondition is that the season
/// exists. `displayOrder` is caller-supplied, exactly as
/// [LinkFixtureToRound] does it.""",
            """/// Unlike [LinkFixtureToRound] there is no lifecycle status to gate against
/// (a season carries none). `displayOrder` is caller-supplied, exactly as
/// [LinkFixtureToRound] does it.
///
/// Two preconditions:
/// 1. **The season exists.**
/// 2. **The season is a month season** â€” its `[startAt, endAt)` window stays
///    inside one calendar month (`competition.season_not_monthly`).
///
/// The second exists because the contest is the calendar month, not the
/// league. `ListCurrentMonthFixtures` resolves, per competition, the season
/// whose window covers now â€” and a league season's window covers the current
/// month too. A fixture linked to a league season is therefore served to the
/// client carrying THAT season id, so `SubmitFixturePrediction` resolves (or
/// auto-creates) the participant there, and those points never reach the
/// monthly standings. That split is not detectable at prediction time: every
/// layer behaves correctly on the season id it is handed. It has to be
/// refused at the only point where the wrong season is chosen â€” here.""",
        ),
        (
            """    // The season must exist.
    final seasonResult = await _competitions.findSeason(sId);
    if (seasonResult is Err<CompetitionSeason>) {
      return Result.err(seasonResult.error);
    }
""",
            """    // The season must exist.
    final seasonResult = await _competitions.findSeason(sId);
    if (seasonResult is Err<CompetitionSeason>) {
      return Result.err(seasonResult.error);
    }
    final season = (seasonResult as Ok<CompetitionSeason>).value;
    if (!_isMonthSn½éÍ½¸¡Í•…Í½¸¤¤ì(€€€€€É•ÑÕÉ¸I•ÍÕ±Ğ¹•ÉÈ (€€€€€€€ÁÁÉÉ½È¹¥¹Ù…É¥…¹Ğ (€€€€€€€€€€½µÁ•Ñ¥Ñ¥½¸¹Í•…Í½¹}¹½Ñ}µ½¹Ñ¡±äœ°(€€€€€€€€€€M•…Í½¸€ˆ‘íÍ•…Í½¸¹±…‰•±ôˆÍÁ…¹Ìµ½É”Ñ¡…¸½¹”…±•¹‘…Èµ½¹Ñ ì€œ(€€€€€€€€€€€€€€™¥áÑÕÉ•Ìµ…ä½¹±ä‰”±¥¹­•Ñ¼„µ½¹Ñ Í•…Í½¸œ°(€€€€€€€€¤°(€€€€€€¤ì(€€€ô(ˆˆˆ°(€€€€€€€€¤°(€€€€€€€€ (€€€€€€€€€€€€ˆˆˆ€€€™¥¹…°Í…Ù•€ô…İ…¥Ğ}™¥áÑÕÉ•AÉ•‘¥Ñ¥½¹Ì¹±¥¹­¥áÑÕÉ•Q½M•…Í½¸¡±¥¹¬¤ì(€€€É•ÑÕÉ¸Íİ¥Ñ €¡Í…Ù•¤ì(€€€€€=¬ñÙ½¥ø ¤€ôøI•ÍÕ±Ğ¹½¬¡±¥¹¬¤°(€€€€€ÉÈñÙ½¥ø é™¥¹…°•ÉÉ½È¤€ôøI•ÍÕ±Ğ¹•ÉÈ¡•ÉÉ½È¤°(€€€ôì(€ô)ôˆˆˆ°(€€€€€€€€€€€€ˆˆˆ€€€™¥¹…°Í…Ù•€ô…İ…¥Ğ}™¥áÑÕÉ•AÉ•‘¥Ñ¥½¹Ì¹±¥¹­¥áÑÕÉ•Q½M•…Í½¸¡±¥¹¬¤ì(€€€É•ÑÕÉ¸Íİ¥Ñ €¡Í…Ù•¤ì(€€€€€=¬ñÙ½¥ø ¤€ôøI•ÍÕ±Ğ¹½¬¡±¥¹¬¤°(€€€€€ÉÈñÙ½¥ø é™¥¹…°•ÉÉ½È¤€ôøI•ÍÕ±Ğ¹•ÉÈ¡•ÉÉ½È¤°(€€€ôì(€ô((€€¼¼¼]¡•Ñ¡•ÈmÍ•…Í½¹tÌİ¥¹‘½ÜÍÑ…åÌ¥¹Í¥‘”„Í¥¹±”…±•¹‘…Èµ½¹Ñ ¸(€€¼¼¼(€€¼¼¼•¹‘Ñ€¥Ì•á±ÕÍ¥Ù”°Í¼„µ½¹Ñ Ñ¡…Ğ•¹‘Ì•á…Ñ±ä…ĞÑ¡”™¥ÉÍĞ¥¹ÍÑ…¹Ğ(€€¼¼¼½˜Ñ¡”¹•áĞµ½¹Ñ ¥ÌÍÑ¥±°½¹”µ½¹Ñ èÑ¡”±…ÍĞ¥¹±Õ‘•¥¹ÍÑ…¹Ğ¥Ì(€€¼¼¼Ñ•ÍÑ•°¹½ĞÑ¡”‰½Õ¹‘…Éä¥ÑÍ•±˜¸(€ÍÑ…Ñ¥Œ‰½½°}¥Í5½¹Ñ¡M•…Í½¸¡½µÁ•Ñ¥Ñ¥½¹M•…Í½¸Í•…Í½¸¤ì(€€€™¥¹…°ÍÑ…ÉĞ€ôÍ•…Í½¸¹ÍÑ…ÉÑĞ¹Ñ½UÑŒ ¤ì(€€€™¥¹…°±…ÍÑ%¹±Õ‘•€ôÍ•…Í½¸¹•¹‘Ğ¹Ñ½UÑŒ ¤¹ÍÕ‰ÑÉ…Ğ (€€€€€½¹ÍĞÕÉ…Ñ¥½¸¡µ¥É½Í•½¹‘Ìè€Ä¤°(€€€€¤ì(€€€É•ÑÕÉ¸ÍÑ…ÉĞ¹å•…È€ôô±…ÍÑ%¹±Õ‘•¹å•…È€˜˜(€€€€€€€ÍÑ…ÉĞ¹µ½¹Ñ €ôô±…ÍÑ%¹±Õ‘•¹µ½¹Ñ ì(€ô)ôˆˆˆ°(€€€€€€€€¤°(€€€t°(¤(()‘•˜ÉÕ¸¡µ°İõI==P¤è(€€€ÁÉ¥¹Ğ¡˜ˆíµ‘ôˆ¤(€€€¥˜Idè(€€€€€€€É•ÑÕÉ¸(€€€È€ôÍÕ‰ÁÉ½•ÍÌ¹ÉÕ¸¡µ°Í¡•±°õQÉÕ”°İõİ¤(€€€¥˜È¹É•ÑÕÉ¹½‘”€„ô€Àè(€€€€€€€ÍåÌ¹•á¥Ğ¡È¹É•ÑÕÉ¹½‘”¤(()ÉÕ¸ ‰‘…ÉĞ™½Éµ…ĞÁ…­…•Ì½…ÁÁ±¥…Ñ¥½¸½±¥ˆ½ÍÉŒ½½µÁ•Ñ¥Ñ¥½¸½±¥¹­}™¥áÑÕÉ•}Ñ½}Í•…Í½¸¹‘…ÉĞˆ¤)ÉÕ¸ ‰Á…­…•Ì½…ÁÁ±¥…Ñ¥½¸€˜˜™±ÕÑÑ•ÈÑ•ÍĞ€´µÉ•Á½ÉÑ•Èõ™…¥±ÕÉ•Ìµ½¹±äˆ¤)ÉÕ¸ ‰…ÁÁÌ½Í•ÉÙ•È€˜˜™±ÕÑÑ•ÈÑ•ÍĞ€´µÉ•Á½ÉÑ•Èõ™…¥±ÕÉ•Ìµ½¹±äˆ¤()¥˜¹½ĞIdè(€€€1=€ôI==P€¼€‰‘½Ì½¡•­Á½¥¹ÑÌ½Í•ÍÍ¥½¸µ±½œ¹µˆ(€€€1=¹İÉ¥Ñ•}Ñ•áĞ (€€€€€€€1=¹É•…‘}Ñ•áĞ¡•¹½‘¥¹œô‰ÕÑ˜´àˆ¤(€€€€€€€€¬€‰q¸ÈÀÈØ´Àä´ÀÔqÔÈÀÄĞ€ÈÙ}µ½¹Ñ¡}Í•…Í½¹}±¥¹­}Õ…Éè€ˆ(€€€€€€€€‰qÔÀØÈİqÔÀØĞÑqÔÀØÉ‰qÔÀØĞÉqÔÀØÈàqÔÀØÈİqÔÀØĞÑqÔÀØÈáqÔÀØĞÙqÔÀØÑ…qÔÀØĞáqÔÀØÑ„€ˆ(€€€€€€€€‰qÔÀØĞáqÔÀØÌÅqÔÀØÈİqÔÀØÈÄqÔÀØÈİqÔÀØĞÙqÔÀØĞÉqÔÀØÌÍqÔÀØÈİqÔÀØĞÔ€ĞÈÌ¼ÌÈè€ˆ(€€€€€€€€‰1¥ÍÑÕÉÉ•¹Ñ5½¹Ñ¡¥áÑÕÉ•ÌqÔÀØÑ…qÔÀØÈÍqÔÀØÉ•qÔÀØÌÀqÔÀØĞÑqÔÀØĞÍqÔÀØĞĞ€ˆ(€€€€€€€€‰qÔÀØĞÕqÔÀØÌÍqÔÀØÈİqÔÀØÈáqÔÀØĞÉqÔÀØÈäqÔÀØÈİqÔÀØĞÑqÔÀØĞÕqÔÀØĞáqÔÀØÌÍqÔÀØĞÔ€ˆ(€€€€€€€€‰qÔÀØÈİqÔÀØĞÑqÔÀØÌÁqÔÀØÑ„qÔÀØÉ…qÔÀØÍ…qÔÀØÌİqÔÀØÔÅqÔÀØÑ„€ˆ(€€€€€€€€‰qÔÀØĞÙqÔÀØÈİqÔÀØĞÅqÔÀØÌÁqÔÀØÉ…qÔÀØĞÜqÔÀØÈİqÔÀØĞÑqÔÀØĞÑqÔÀØÉ‘qÔÀØÌáqÔÀØÈåqÔÀØÁŒ€ˆ(€€€€€€€€‰qÔÀØĞáqÔÀØĞÙqÔÀØÈİqÔÀØĞÅqÔÀØÌÁqÔÀØÈäqÔÀØĞÕqÔÀØĞáqÔÀØÌÍqÔÀØĞÔ€ˆ(€€€€€€€€‰qÔÀØÈİqÔÀØĞÑqÔÀØÉ™qÔÀØĞáqÔÀØÌÅqÔÀØÑ„qÔÀØÉ…qÔÀØÍ…qÔÀØÌİqÔÀØÔÅqÔÀØÑ„€ˆ(€€€€€€€€‰qÔÀØÈİqÔÀØĞÑqÔÀØÌÑqÔÀØĞİqÔÀØÌÄqÔÀØÈÍqÔÀØÑ…qÔÀØÌÙqÔÀØÑ‰qÔÀØÈİqÔÀØÅˆì€ˆ(€€€€€€€€‰qÔÀØĞÅqÔÀØĞÕqÔÀØÈáqÔÀØÈİqÔÀØÌÅqÔÀØÈİqÔÀØÈäqÔÀØĞÕqÔÀØÌÅqÔÀØÈáqÔÀØĞáqÔÀØÌİqÔÀØÈä€ˆ(€€€€€€€€‰qÔÀØĞİqÔÀØĞÙqÔÀØÈİqÔÀØĞÌqÔÀØÉ…qÔÀØÑ™qÔÀØĞÉqÔÀØÉ™qÔÀØÔÅqÔÀØĞÔ€ˆ(€€€€€€€€‰qÔÀØĞÑqÔÀØĞÑqÔÀØÌåqÔÀØĞÕqÔÀØÑ…qÔÀØĞĞqÔÀØÈáqÔÀØĞÕqÔÀØÌåqÔÀØÌÅqÔÀØÔÅqÔÀØĞÄ€ˆ(€€€€€€€€‰qÔÀØÌÁqÔÀØĞÑqÔÀØĞÌq