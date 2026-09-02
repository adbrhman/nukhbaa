#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01_results_scoring_season_picker.py

الإصلاح: استبدال سلسلة الاختيار المكسورة (المسابقة ← الموسم ← الجولة ←
المباراة) في ResultsScoringSection بسلسلة مباشرة (المسابقة ← الموسم ←
المباراة) عبر ودجت جديدة SeasonFixturePickerField.

السبب: منذ التحول لنموذج Per-Fixture (Season→Fixture مباشرة، Axiom 4
Amendment)، لم تعد المباريات تُنشأ تحت جولة بالضرورة. RoundPickerField كان
يعرض "لا توجد جولات لهذا الموسم" لأي مباراة من هذا النوع، فتبقى شاشة
النتائج والاحتساب عالقة دائمًا ولا يمكن تسجيل نتيجة/احتساب/ترحيل لأي مباراة
حديثة.

تحقّق مسبق (قبل توليد هذا السكربت): seasonFixturesProvider وSeasonFixtureCardDto
موجودان فعليًا ومستخدَمان في fixture_schedule_section.dart وfixture_prediction
عبر GET /seasons/{id}/fixtures — لا حاجة لأي تغيير خادم/DB/ARB، القيم النصية
كلها تُعاد استخدامها (adminSelectFixtureLabel وadminNoFixturesHint
وadminFixtureIncompleteDataLabel الموجودة أصلًا في admin_pickers.dart).

لا يحذف هذا السكربت RoundPickerField أو FixturePickerField القديمتين —
تصبحان يتيمتين فعليًا بعد هذا الإصلاح (تحقّق: كل استدعاءاتهما كانت محصورة
في هذا الملف فقط) لكن حذفهما متروك عمدًا لسكربت لاحق منفصل (قاعدة إصلاح
واحد لكل رسالة).

الاستخدام:
    cd ~/nukhbaa-backup-1787537565
    python3 01_results_scoring_season_picker.py

آمن للتشغيل المتكرر (idempotent): إن وجد SeasonFixturePickerField موجودة
مسبقًا في admin_pickers.dart يتوقف بلا أي تعديل.
"""

from __future__ import annotations

import subprocess
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path.cwd()
PICKERS = REPO_ROOT / "apps/mobile/lib/features/admin/widgets/admin_pickers.dart"
SECTION = (
    REPO_ROOT
    / "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart"
)
SESSION_LOG = REPO_ROOT / "docs/checkpoints/session-log.md"


def fail(msg: str) -> None:
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(1)


def must_replace(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0:
        fail(
            f"لم يُعثر على النمط المتوقع ({label}) — الملف الفعلي مختلف عن "
            "المتوقَّع. توقفت بلا أي تعديل. يلزم فحص يدوي قبل إعادة المحاولة."
        )
    if count > 1:
        fail(
            f"النمط ({label}) تكرر {count} مرة بدل مرة واحدة — غير آمن "
            "لاستبدال تلقائي. توقفت بلا أي تعديل."
        )
    return text.replace(old, new, 1)


def main() -> None:
    if not PICKERS.exists() or not SECTION.exists():
        fail(
            "المسارات المتوقعة غير موجودة — تأكد من التشغيل من جذر المستودع "
            "الصحيح (~/nukhbaa-backup-1787537565)."
        )

    pickers_src = PICKERS.read_text(encoding="utf-8")
    section_src = SECTION.read_text(encoding="utf-8")

    if "class SeasonFixturePickerField" in pickers_src:
        print("↷ SeasonFixturePickerField موجودة مسبقًا — لا شيء لفعله. توقّف.")
        return

    if "seasonFixturesProvider" not in (
        REPO_ROOT
        / "apps/mobile/lib/features/fixture_prediction/fixture_prediction_providers.dart"
    ).read_text(encoding="utf-8"):
        fail(
            "seasonFixturesProvider غير موجود في fixture_prediction_providers.dart "
            "— حالة المستودع الفعلية مختلفة عمّا تحقّقتُ منه. توقفت بلا أي تعديل."
        )

    # --- 1) admin_pickers.dart: إضافة import ---------------------------------
    pickers_src = must_replace(
        pickers_src,
        "import '../../competition/competition_providers.dart';",
        "import '../../competition/competition_providers.dart';\n"
        "import '../../fixture_prediction/fixture_prediction_providers.dart';",
        "import fixture_prediction_providers",
    )

    # --- 2) admin_pickers.dart: إضافة SeasonFixturePickerField في النهاية ----
    old_tail = (
        "  String _fixtureLabel(RoundFixtureCardDto fixture, AppLocalizations l10n) {\n"
        "    final String? home = fixture.homeTeam;\n"
        "    final String? away = fixture.awayTeam;\n"
        "    if (home == null || away == null) {\n"
        "      return l10n.adminFixtureIncompleteDataLabel;\n"
        "    }\n"
        "    return '$home × $away';\n"
        "  }\n"
        "}"
    )
    new_class = (
        "\n\n"
        "/// قائمة المباراة المنسدلة (الموسم ← المباراة مباشرة، بلا خطوة جولة).\n"
        "/// تعرض الفريقين — أو تنويهاً عند نقص بيانات الهوية — وتُخرج fixtureId\n"
        "/// فقط، بلا إدخال UUID يدوي. تُستخدم في الشاشات التي تتعامل مع كل مباريات\n"
        "/// الموسم مباشرة (خلافاً لـ[FixturePickerField] المرتبطة بجولة).\n"
        "/// [keyPrefix] يُميّز مفاتيح الودجت بين الأقسام المختلفة.\n"
        "class SeasonFixturePickerField extends ConsumerWidget {\n"
        "  const SeasonFixturePickerField({\n"
        "    super.key,\n"
        "    required this.keyPrefix,\n"
        "    required this.seasonId,\n"
        "    required this.enabled,\n"
        "    required this.selectedId,\n"
        "    required this.onSelected,\n"
        "  });\n"
        "\n"
        "  final String keyPrefix;\n"
        "  final String seasonId;\n"
        "  final bool enabled;\n"
        "  final String? selectedId;\n"
        "  final ValueChanged<SeasonFixtureCardDto> onSelected;\n"
        "\n"
        "  @override\n"
        "  Widget build(BuildContext context, WidgetRef ref) {\n"
        "    final l10n = AppLocalizations.of(context);\n"
        "    final AsyncValue<List<SeasonFixtureCardDto>> fixtures = ref.watch(\n"
        "      seasonFixturesProvider(seasonId),\n"
        "    );\n"
        "    return fixtures.when(\n"
        "      loading: () => const LinearProgressIndicator(),\n"
        "      error: (Object error, StackTrace _) => InputDecorator(\n"
        "        decoration: InputDecoration(\n"
        "          labelText: l10n.adminSelectFixtureLabel,\n"
        "          border: const OutlineInputBorder(),\n"
        "        ),\n"
        "        child: Text(ErrorPresenter.message(error as AppError)),\n"
        "      ),\n"
        "      data: (List<SeasonFixtureCardDto> list) {\n"
        "        if (list.isEmpty) {\n"
        "          return InputDecorator(\n"
        "            decoration: InputDecoration(\n"
        "              labelText: l10n.adminSelectFixtureLabel,\n"
        "              border: const OutlineInputBorder(),\n"
        "            ),\n"
        "            child: Text(l10n.adminNoFixturesHint),\n"
        "          );\n"
        "        }\n"
        "        final String? value = list.any((f) => f.fixtureId == selectedId)\n"
        "            ? selectedId\n"
        "            : null;\n"
        "        return DropdownButtonFormField<String>(\n"
        "          key: Key('$keyPrefix.fixtureField'),\n"
        "          initialValue: value,\n"
        "          decoration: InputDecoration(\n"
        "            labelText: l10n.adminSelectFixtureLabel,\n"
        "            border: const OutlineInputBorder(),\n"
        "          ),\n"
        "          items: <DropdownMenuItem<String>>[\n"
        "            for (final SeasonFixtureCardDto fixture in list)\n"
        "              DropdownMenuItem<String>(\n"
        "                key: Key('$keyPrefix.fixtureField.${fixture.fixtureId}'),\n"
        "                value: fixture.fixtureId,\n"
        "                child: Text(_fixtureLabel(fixture, l10n)),\n"
        "              ),\n"
        "          ],\n"
        "          onChanged: !enabled\n"
        "              ? null\n"
        "              : (String? id) {\n"
        "                  if (id == null) return;\n"
        "                  final SeasonFixtureCardDto fixture = list.firstWhere(\n"
        "                    (f) => f.fixtureId == id,\n"
        "                  );\n"
        "                  onSelected(fixture);\n"
        "                },\n"
        "        );\n"
        "      },\n"
        "    );\n"
        "  }\n"
        "\n"
        "  String _fixtureLabel(SeasonFixtureCardDto fixture, AppLocalizations l10n) {\n"
        "    final String? home = fixture.homeTeam;\n"
        "    final String? away = fixture.awayTeam;\n"
        "    if (home == null || away == null) {\n"
        "      return l10n.adminFixtureIncompleteDataLabel;\n"
        "    }\n"
        "    return '$home × $away';\n"
        "  }\n"
        "}"
    )
    pickers_src = must_replace(
        pickers_src, old_tail, old_tail + new_class, "نهاية FixturePickerField"
    )

    # --- 3) results_scoring_section.dart: تعليق التوثيق العلوي ---------------
    section_src = must_replace(
        section_src,
        "/// النتائج والاحتساب — تسجيل نتيجة مباراة، احتساب المباراة، ترحيلها\n"
        "/// للسجل، وتقرير المباراة التفصيلي.\n"
        "///\n"
        "/// معرّف المباراة يُختار من قوائم منسدلة (المسابقة ← الموسم ← الجولة ←\n"
        "/// المباراة)، وليس بإدخال UUID يدوي — مطابقةً لنمط\n"
        "/// `RoundAdministrationSection`/`FixtureScheduleSection`.",
        "/// النتائج والاحتساب — تسجيل نتيجة مباراة، احتساب المباراة، ترحيلها\n"
        "/// للسجل، وتقرير المباراة التفصيلي.\n"
        "///\n"
        "/// معرّف المباراة يُختار من قوائم منسدلة (المسابقة ← الموسم ← المباراة)\n"
        "/// مباشرة، وليس بإدخال UUID يدوي — مطابقةً لنمط `FixtureScheduleSection`.\n"
        "/// لا خطوة جولة هنا: المباريات تُنشأ الآن مباشرة تحت الموسم (Axiom 4\n"
        "/// Amendment) ولم تعد مرتبطة بأي جولة بالضرورة، فمنتقي الجولة القديم\n"
        "/// (RoundPickerField) كان يترك هذه الشاشة عالقة على \"لا توجد جولات لهذا\n"
        "/// الموسم\" لأي مباراة من هذا النوع.",
        "تعليق التوثيق العلوي",
    )

    # --- 4) حذف حقل _resultRoundId --------------------------------------------
    section_src = must_replace(
        section_src,
        "  String? _resultCompetitionId;\n"
        "  String? _resultSeasonId;\n"
        "  String? _resultRoundId;\n"
        "  String? _fixtureId;",
        "  String? _resultCompetitionId;\n"
        "  String? _resultSeasonId;\n"
        "  String? _fixtureId;",
        "حذف _resultRoundId",
    )

    # --- 5) تحديث العنوان الفرعي ------------------------------------------------
    section_src = must_replace(
        section_src,
        "subtitle: 'اختر المسابقة والموسم والجولة ثم المباراة وسجّل نتيجتها',",
        "subtitle: 'اختر المسابقة والموسم ثم المباراة وسجّل نتيجتها',",
        "العنوان الفرعي",
    )

    # --- 6) استبدال سلسلة Round→Fixture بـ SeasonFixturePickerField ----------
    old_chain = (
        "                onSelected: (CompetitionDto competition) => setState(() {\n"
        "                  _resultCompetitionId = competition.id;\n"
        "                  _resultSeasonId = null;\n"
        "                  _resultRoundId = null;\n"
        "                  _fixtureId = null;\n"
        "                }),\n"
        "              ),\n"
        "              if (_resultCompetitionId != null) ...[\n"
        "                const SizedBox(height: AppSpacing.md),\n"
        "                SeasonPickerField(\n"
        "                  competitionId: _resultCompetitionId!,\n"
        "                  enabled: !resultInFlight,\n"
        "                  selectedId: _resultSeasonId,\n"
        "                  onSelected: (String seasonId) => setState(() {\n"
        "                    _resultSeasonId = seasonId;\n"
        "                    _resultRoundId = null;\n"
        "                    _fixtureId = null;\n"
        "                  }),\n"
        "                ),\n"
        "              ],\n"
        "              if (_resultSeasonId != null) ...[\n"
        "                const SizedBox(height: AppSpacing.md),\n"
        "                RoundPickerField(\n"
        "                  keyPrefix: 'admin.results.record',\n"
        "                  seasonId: _resultSeasonId!,\n"
        "                  enabled: !resultInFlight,\n"
        "                  selectedId: _resultRoundId,\n"
        "                  onSelected: (RoundDto round) => setState(() {\n"
        "                    _resultRoundId = round.id;\n"
        "                    _fixtureId = null;\n"
        "                  }),\n"
        "                ),\n"
        "              ],\n"
        "              if (_resultRoundId != null) ...[\n"
        "                const SizedBox(height: AppSpacing.md),\n"
        "                FixturePickerField(\n"
        "                  keyPrefix: 'admin.results.record',\n"
        "                  roundId: _resultRoundId!,\n"
        "                  enabled: !resultInFlight,\n"
        "                  selectedId: _fixtureId,\n"
        "                  onSelected: (RoundFixtureCardDto fixture) => setState(() {\n"
        "                    _fixtureId = fixture.fixtureId;\n"
        "                  }),\n"
        "                ),\n"
        "              ],"
    )
    new_chain = (
        "                onSelected: (CompetitionDto competition) => setState(() {\n"
        "                  _resultCompetitionId = competition.id;\n"
        "                  _resultSeasonId = null;\n"
        "                  _fixtureId = null;\n"
        "                }),\n"
        "              ),\n"
        "              if (_resultCompetitionId != null) ...[\n"
        "                const SizedBox(height: AppSpacing.md),\n"
        "                SeasonPickerField(\n"
        "                  competitionId: _resultCompetitionId!,\n"
        "                  enabled: !resultInFlight,\n"
        "                  selectedId: _resultSeasonId,\n"
        "                  onSelected: (String seasonId) => setState(() {\n"
        "                    _resultSeasonId = seasonId;\n"
        "                    _fixtureId = null;\n"
        "                  }),\n"
        "                ),\n"
        "              ],\n"
        "              if (_resultSeasonId != null) ...[\n"
        "                const SizedBox(height: AppSpacing.md),\n"
        "                SeasonFixturePickerField(\n"
        "                  keyPrefix: 'admin.results.record',\n"
        "                  seasonId: _resultSeasonId!,\n"
        "                  enabled: !resultInFlight,\n"
        "                  selectedId: _fixtureId,\n"
        "                  onSelected: (SeasonFixtureCardDto fixture) => setState(() {\n"
        "                    _fixtureId = fixture.fixtureId;\n"
        "                  }),\n"
        "                ),\n"
        "              ],"
    )
    section_src = must_replace(section_src, old_chain, new_chain, "سلسلة المنتقيات")

    PICKERS.write_text(pickers_src, encoding="utf-8")
    SECTION.write_text(section_src, encoding="utf-8")
    print("✓ كُتب التعديل في الملفين.")

    # --- تنسيق (best effort) --------------------------------------------------
    for tool in (["dart", "format"], ["flutter", "format"]):
        try:
            subprocess.run(
                [*tool, str(PICKERS), str(SECTION)],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            print(f"✓ تنسيق ({' '.join(tool)}) نجح.")
            break
        except FileNotFoundError:
            continue
        except subprocess.CalledProcessError as e:
            print(f"⚠ فشل تنسيق ({' '.join(tool)}):\n{e.stdout}\n{e.stderr}")
            break

    # --- flutter analyze: بوابة إلزامية قبل أي commit --------------------------
    try:
        result = subprocess.run(
            ["flutter", "analyze", "apps/mobile"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=600,
        )
        print(result.stdout)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            fail(
                "flutter analyze فشل — الملفان مُعدَّلان على القرص لكن لن يتم "
                "أي commit. راجع الأخطاء أعلاه، صحّحها يدويًا، ثم شغّل "
                "commit بنفسك بمسارات محددة."
            )
        print("✓ flutter analyze: نظيف.")
    except FileNotFoundError:
        print(
            "⚠ لم يُعثر على أمر flutter في PATH — تخطّي analyze. لا تعتبر "
            "هذا الإصلاح مكتملًا قبل تشغيل flutter analyze يدويًا."
        )

    # --- تسجيل checkpoint -------------------------------------------------------
    ts = datetime.now().strftime("%H:%M")
    log_line = (
        f"- [{ts}] إصلاح: استبدال سلسلة الجولة اليتيمة (RoundPickerField/"
        "FixturePickerField) بمنتقي مباراة مباشر للموسم (SeasonFixturePickerField "
        "جديدة) في ResultsScoringSection — يعالج تعطّل شاشة النتائج والاحتساب "
        "دائمًا على \"لا توجد جولات لهذا الموسم\" لأي مباراة أُنشئت بعد التحول "
        "لنموذج Per-Fixture؛ RoundPickerField/FixturePickerField أصبحتا يتيمتين "
        "فعليًا (صفر مستهلك) وتُركتا للحذف في سكربت لاحق منفصل | ملفات: "
        "apps/mobile/lib/features/admin/widgets/admin_pickers.dart, "
        "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart "
        "| اختبار: flutter analyze نظيف (انظر المخرجات أعلاه)\n"
    )
    with SESSION_LOG.open("a", encoding="utf-8") as f:
        f.write(log_line)
    print(f"✓ سُجِّل checkpoint في {SESSION_LOG}.")

    # --- git add + commit (بلا -A، بمسارات محددة) --------------------------------
    paths = [
        "apps/mobile/lib/features/admin/widgets/admin_pickers.dart",
        "apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart",
        "docs/checkpoints/session-log.md",
    ]
    subprocess.run(["git", "add", *paths], cwd=REPO_ROOT, check=True)
    commit_msg = (
        "fix(admin/results-scoring): season-scoped fixture picker\n\n"
        "ResultsScoringSection used RoundPickerField -> FixturePickerField, but "
        "fixtures are now linked directly to a season (no round required), so "
        "the screen got permanently stuck on 'no rounds for this season' for "
        "any fixture created after the Per-Fixture migration.\n\n"
        "Adds SeasonFixturePickerField (mirrors FixturePickerField, backed by "
        "the already-existing seasonFixturesProvider) and rewires the screen to "
        "Competition -> Season -> Fixture directly. No server/DB/ARB changes "
        "needed. RoundPickerField/FixturePickerField are now fully orphaned "
        "(zero consumers) but intentionally left in place for a follow-up "
        "cleanup script."
    )
    subprocess.run(["git", "commit", "-m", commit_msg], cwd=REPO_ROOT, check=True)
    print("✓ تم commit محليًا.")
    print()
    print("== git show --stat HEAD ==")
    subprocess.run(["git", "show", "--stat", "HEAD"], cwd=REPO_ROOT, check=False)
    print()
    print(
        "لم يُنفَّذ push بعد. راجع git diff/git show أعلاه، ثم إن كان كل شيء "
        "سليمًا:\n    git push origin main"
    )


if __name__ == "__main__":
    main()
