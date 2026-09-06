#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""40_remove_fixture_button — حذف مباراة من الموسم: لوحة المشرف (2/2)."""
import os, json, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
M = os.path.join(ROOT, "apps/mobile")
assert os.path.isdir(M), "apps/mobile not found under %s" % ROOT


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def patch(rel, old, new, count=1):
    p = os.path.join(M, rel)
    s = read(p)
    assert s.count(old) == count, "anchor x%d != %d in %s" % (s.count(old), count, rel)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new, count))
    print("patched", rel)


# ------------------------------------------------------------ controller
patch(
    "lib/features/admin/admin_providers.dart",
    """/// نتيجة دمج تسجيل المباراة وربطها بالجولة — نجاح فقط إذا نجحت العمليتان معاً.""",
    """/// يفكّ ربط مباراة بموسمها (`RemoveFixtureFromSeason`). الخادم يرفض الحذف
/// إن كانت المباراة قد تلقّت أي توقّع أو سُجّلت لها نتيجة، فلا يحتاج هذا
/// المتحكّم إلى فحص مسبق: رسالة الرفض تصل عبر `AppError` وتُعرض كما هي.
///
/// الحالة `true` تعني أن رابطاً حُذف فعلاً، و`false` أنه لم يكن موجودًا —
/// وكلاهما نجاح (العملية عديمة الأثر عند التكرار).
@riverpod
class RemoveFixtureController extends _$RemoveFixtureController {
  CompetitionApi get _competitionApi => ref.read(competitionApiProvider);

  @override
  AsyncValue<bool>? build() => null;

  /// يفكّ ربط [fixtureId] بـ[seasonId].
  Future<void> remove({
    required String seasonId,
    required String fixtureId,
  }) async {
    state = const AsyncValue.loading();

    final result = await _competitionApi.removeFixtureFromSeason(
      seasonId: seasonId,
      fixtureId: fixtureId,
    );
    if (result is Err<bool>) {
      state = AsyncValue.error(result.error, StackTrace.current);
      return;
    }
    state = AsyncValue.data((result as Ok<bool>).value);

    // نفس الإبطالين اللذين يجريهما AddMatchController، بالاتجاه المعاكس.
    ref.invalidate(seasonFixturesProvider(seasonId));
    ref.invalidate(currentMonthFixturesProvider);
  }
}

/// نتيجة دمج تسجيل المباراة وربطها بالجولة — نجاح فقط إذا نجحت العمليتان معاً.""",
)

# ----------------------------------------------------------------- state
SEC = "lib/features/admin/screens/sections/fixture_schedule_section.dart"

patch(
    SEC,
    """    final bool canSubmitCorrection =
        !correctInFlight &&""",
    """    final AsyncValue<bool>? removeState = ref.watch(
      removeFixtureControllerProvider,
    );
    final bool removeInFlight = removeState is AsyncLoading<bool>;
    final bool canSubmitCorrection =
        !correctInFlight &&""",
)

# ---------------------------------------------------------------- the UI
patch(
    SEC,
    """              AdminPrimaryButton(
                key: const Key('admin.fixtures.correct.submit'),
                label: l10n.adminCorrectFixtureButton,
                icon: Icons.edit_calendar_rounded,
                loading: correctInFlight,
                onPressed: canSubmitCorrection ? _correctFixture : null,
              ),""",
    """              AdminPrimaryButton(
                key: const Key('admin.fixtures.correct.submit'),
                label: l10n.adminCorrectFixtureButton,
                icon: Icons.edit_calendar_rounded,
                loading: correctInFlight,
                onPressed: canSubmitCorrection ? _correctFixture : null,
              ),
              // Removal lives inside the correction scope on purpose: the
              // admin has already picked the exact fixture here, so it needs
              // no picker of its own — and a delete under every row of a
              // browse list is a misclick waiting to happen.
              if (_correctFixtureId != null) ...[
                const SizedBox(height: AppSpacing.md),
                if (removeState is AsyncError<bool>)
                  AdminErrorBanner(
                    key: const Key('admin.fixtures.remove.error'),
                    message: ErrorPresenter.message(
                      removeState.error as AppError,
                    ),
                  ),
                if (removeState is AsyncData<bool>)
                  AdminSuccessBanner(
                    key: const Key('admin.fixtures.remove.result'),
                    message: l10n.adminRemoveFixtureFromSeasonSuccess,
                  ),
                const SizedBox(height: AppSpacing.md),
                AdminSecondaryButton(
                  key: const Key('admin.fixtures.remove.submit'),
                  label: l10n.adminRemoveFixtureFromSeasonButton,
                  icon: Icons.delete_outline_rounded,
                  loading: removeInFlight,
                  onPressed: removeInFlight ? null : _confirmRemoveFixture,
                ),
              ],""",
)

# --------------------------------------------------------------- handler
patch(
    SEC,
    """    _correctAwayTeamFocusNode.dispose();
    super.dispose();
  }
""",
    """    _correctAwayTeamFocusNode.dispose();
    super.dispose();
  }

  /// يطلب تأكيدًا صريحًا ثم يحذف. الحوار يذكر اسمي الفريقين لا معرّف
  /// المباراة، لأن المعرّف لا يميّز شيئًا في ذهن المشرف.
  Future<void> _confirmRemoveFixture() async {
    final l10n = AppLocalizations.of(context);
    final String seasonId = _correctSeasonId!;
    final String fixtureId = _correctFixtureId!;
    final String home = _correctHomeTeamController.text.trim();
    final String away = _correctAwayTeamController.text.trim();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('admin.fixtures.remove.confirm'),
        title: Text(l10n.adminRemoveFixtureFromSeasonButton),
        content: Text(l10n.adminRemoveFixtureFromSeasonConfirm(home, away)),
        actions: <Widget>[
          TextButton(
            key: const Key('admin.fixtures.remove.confirm.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.adminRemoveFixtureCancelButton),
          ),
          TextButton(
            key: const Key('admin.fixtures.remove.confirm.ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminRemoveFixtureFromSeasonButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref
        .read(removeFixtureControllerProvider.notifier)
        .remove(seasonId: seasonId, fixtureId: fixtureId);
    if (!mounted) return;

    // بعد حذف ناجح لم يعد للمباراة المختارة وجود، فيُفرَّغ نطاق التصحيح
    // كي لا يبقى نموذج يشير إلى شيء محذوف.
    if (ref.read(removeFixtureControllerProvider) is AsyncData<bool>) {
      setState(() {
        _correctFixtureId = null;
        _correctHomeTeamController.clear();
        _correctAwayTeamController.clear();
        _correctHomeTeamId = null;
        _correctAwayTeamId = null;
        _correctKickoffLocal = null;
      });
    }
  }
""",
)

# ------------------------------------------------------------------ l10n
patch(
    "lib/l10n/app_ar.arb",
    '  "adminTeamNotInCatalogHint"',
    '  "adminRemoveFixtureFromSeasonButton": "حذف المباراة من الشهر",\n'
    '  "adminRemoveFixtureFromSeasonConfirm": "سيُحذف ربط «{home} × {away}» بمسابقة الشهر. '
    'لا يمكن الحذف إن كان أحد قد توقّعها أو سُجّلت لها نتيجة.",\n'
    '  "@adminRemoveFixtureFromSeasonConfirm": {\n'
    '    "placeholders": { "home": { "type": "String" }, "away": { "type": "String" } }\n'
    '  },\n'
    '  "adminRemoveFixtureFromSeasonSuccess": "تم حذف المباراة من مسابقة الشهر.",\n'
    '  "adminTeamNotInCatalogHint"',
)
patch(
    "lib/l10n/app_en.arb",
    '  "adminTeamNotInCatalogHint"',
    '  "adminRemoveFixtureFromSeasonButton": "Remove from the month",\n'
    '  "adminRemoveFixtureFromSeasonConfirm": "This unlinks \\"{home} vs {away}\\" from the '
    'month\'s competition. It cannot be removed once anyone has predicted it or a result is recorded.",\n'
    '  "@adminRemoveFixtureFromSeasonConfirm": {\n'
    '    "placeholders": { "home": { "type": "String" }, "away": { "type": "String" } }\n'
    '  },\n'
    '  "adminRemoveFixtureFromSeasonSuccess": "Fixture removed from the month\'s competition.",\n'
    '  "adminTeamNotInCatalogHint"',
)
patch(
    "lib/l10n/app_localizations.dart",
    "  String get adminTeamNotInCatalogHint;\n}",
    "  String get adminTeamNotInCatalogHint;\n\n"
    "  /// No description provided for @adminRemoveFixtureFromSeasonButton.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'Remove from the month'**\n"
    "  String get adminRemoveFixtureFromSeasonButton;\n\n"
    "  /// No description provided for @adminRemoveFixtureFromSeasonConfirm.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'This unlinks \"{home} vs {away}\" from the month\\'s competition.'**\n"
    "  String adminRemoveFixtureFromSeasonConfirm(String home, String away);\n\n"
    "  /// No description provided for @adminRemoveFixtureFromSeasonSuccess.\n"
    "  ///\n"
    "  /// In en, this message translates to:\n"
    "  /// **'Fixture removed from the month\\'s competition.'**\n"
    "  String get adminRemoveFixtureFromSeasonSuccess;\n}",
)
patch(
    "lib/l10n/app_localizations_ar.dart",
    "  String get adminTeamNotInCatalogHint =>",
    "  String get adminRemoveFixtureFromSeasonButton => 'حذف المباراة من الشهر';\n\n"
    "  @override\n"
    "  String adminRemoveFixtureFromSeasonConfirm(String home, String away) =>\n"
    "      'سيُحذف ربط «$home × $away» بمسابقة الشهر. لا يمكن الحذف إن كان أحد قد "
    "توقّعها أو سُجّلت لها نتيجة.';\n\n"
    "  @override\n"
    "  String get adminRemoveFixtureFromSeasonSuccess =>\n"
    "      'تم حذف المباراة من مسابقة الشهر.';\n\n"
    "  @override\n"
    "  String get adminTeamNotInCatalogHint =>",
)
patch(
    "lib/l10n/app_localizations_en.dart",
    "  String get adminTeamNotInCatalogHint =>",
    "  String get adminRemoveFixtureFromSeasonButton => 'Remove from the month';\n\n"
    "  @override\n"
    "  String adminRemoveFixtureFromSeasonConfirm(String home, String away) =>\n"
    "      'This unlinks \"$home vs $away\" from the month\\'s competition. It cannot "
    "be removed once anyone has predicted it or a result is recorded.';\n\n"
    "  @override\n"
    "  String get adminRemoveFixtureFromSeasonSuccess =>\n"
    "      'Fixture removed from the month\\'s competition.';\n\n"
    "  @override\n"
    "  String get adminTeamNotInCatalogHint =>",
)

for arb in ("lib/l10n/app_ar.arb", "lib/l10n/app_en.arb"):
    json.loads(read(os.path.join(M, arb)))
print("ARB files still parse as JSON")

TOUCHED = [
    "apps/mobile/lib/features/admin/admin_providers.dart",
    "apps/mobile/" + SEC,
    "apps/mobile/lib/l10n/app_ar.arb",
    "apps/mobile/lib/l10n/app_en.arb",
    "apps/mobile/lib/l10n/app_localizations.dart",
    "apps/mobile/lib/l10n/app_localizations_ar.dart",
    "apps/mobile/lib/l10n/app_localizations_en.dart",
]
for rel in TOUCHED:
    subprocess.run(["dart", "format", os.path.join(ROOT, rel)], check=True)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 40_remove_fixture_button (2/2): زرّ حذف المباراة في لوحة "
    "المشرف فوق مسار الخادم الذي أضافته دفعتا 38 و39. سكن نطاق «تصحيح "
    "المباراة» لا قائمة المباريات: المشرف اختار المباراة بعينها هناك "
    "أصلًا فلا يحتاج منتقيًا ثانيًا، وزرّ حذف تحت كل صفّ في قائمة تصفّح هو "
    "نقرة خاطئة تنتظر أن تقع. حوار تأكيد يذكر اسمي الفريقين لا معرّف "
    "المباراة، ونصّه يقول سلفًا متى يرفض الخادم كي لا يُقرأ الرفض لاحقًا "
    "كعطل. RemoveFixtureController لا يفحص التوقعات ولا النتيجة قبل "
    "النداء: الحارسان في حالة الاستخدام، وتكرارهما في العميل يعني قاعدةً "
    "في مكانين تتباعدان. بعد حذف ناجح يُفرَّغ نموذج التصحيح كي لا يبقى "
    "يشير إلى محذوف، ويُبطَل seasonFixtures وcurrentMonthFixtures — نفس "
    "إبطالَي AddMatchController بالاتجاه المعاكس. ثلاثة مفاتيح ARB مع "
    "التوليد اليدوي، أحدها بمعاملين — "
    + ", ".join(TOUCHED) + "\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = TOUCHED + ["docs/checkpoints/session-log.md"]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "feat(admin): remove a fixture from the month, behind a confirmation"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
