#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""32_calendar_appbar_pill — زر «اليوم» كان يفيض فيبتلع شريط التقويم."""
import os, json, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
M = os.path.join(ROOT, "apps/mobile")
assert os.path.isdir(M), "apps/mobile not found under %s" % ROOT


def patch(rel, old, new, count=1):
    p = os.path.join(M, rel)
    with open(p, encoding="utf-8") as f:
        s = f.read()
    assert s.count(old) == count, "anchor x%d != %d in %s" % (s.count(old), count, rel)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s.replace(old, new, count))
    print("patched", rel)


CAL = "lib/features/fixture_prediction/widgets/fixtures_calendar_page.dart"

# السبب: FilledButtonThemeData في app_theme.dart يفرض
# minimumSize: Size.fromHeight(52)، وشريط التطبيق ارتفاعه 56، فالزرّ مع
# حشوته الرأسية يفيض عن المساحة ويُقتطع، ويأكل معه عرض العنوان الموسّط
# (centerTitle: true) حتى يختفي كلاهما. الحلّ: قدح ستادي بمقاس صريح.
# ولا عنوان أصلًا في المرجع — حبّة دواء «اليوم» وسهم الرجوع فقط.
patch(
    CAL,
    """        title: Text(l10n.fixturesCalendarPickTitle),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: FilledButton(
              key: const Key('fixturesCalendar.today'),
              onPressed: () => Navigator.of(context).pop(today),
              child: Text(l10n.fixturesDateToday),
            ),
          ),
        ],""",
    """        // No title: the reference carries the "today" pill and the back
        // arrow alone. The pill also needs an explicit size — the app's
        // `FilledButtonThemeData` forces `minimumSize: Size.fromHeight(52)`
        // for page-level buttons, which overflows a 56px toolbar and
        // starved the (previously present) centred title of all its width.
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: FilledButton(
              key: const Key('fixturesCalendar.today'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(72, 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(today),
              child: Text(l10n.fixturesDateToday),
            ),
          ),
        ],""",
)

# المفتاح صار يتيمًا بحذف العنوان — يُحذف من الملفات الخمسة على نمط
# 25_remove_orphan_admin_l10n_keys.
patch("lib/l10n/app_ar.arb", '  "fixturesCalendarPickTitle": "اختر التاريخ",\n', "")
patch("lib/l10n/app_en.arb", '  "fixturesCalendarPickTitle": "Pick a date",\n', "")
patch(
    "lib/l10n/app_localizations.dart",
    """  /// No description provided for @fixturesCalendarPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get fixturesCalendarPickTitle;

""",
    "",
)
patch(
    "lib/l10n/app_localizations_ar.dart",
    "\n  @override\n  String get fixturesCalendarPickTitle => 'اختر التاريخ';\n",
    "",
)
patch(
    "lib/l10n/app_localizations_en.dart",
    "\n  @override\n  String get fixturesCalendarPickTitle => 'Pick a date';\n",
    "",
)

with open(os.path.join(M, CAL), encoding="utf-8") as f:
    assert "fixturesCalendarPickTitle" not in f.read(), "key still referenced"
for arb in ("lib/l10n/app_ar.arb", "lib/l10n/app_en.arb"):
    with open(os.path.join(M, arb), encoding="utf-8") as f:
        json.loads(f.read())
print("ARB files still parse as JSON; no reader left for the removed key")

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 32_calendar_appbar_pill: شريط صفحة التقويم كان يظهر "
    "فارغًا إلا من سهم الرجوع: لا عنوان ولا زر «اليوم». السبب "
    "FilledButtonThemeData في app_theme.dart يفرض "
    "minimumSize: Size.fromHeight(52) على كل FilledButton، وارتفاع شريط "
    "التطبيق 56، فالزرّ يفيض ويُقتطع ويأكل عرض العنوان الموسّط "
    "(centerTitle: true) فيختفيان معًا — درس: زرّ مصمَّم لعرض الصفحة لا "
    "يوضع في actions بلا مقاس صريح. صار الزرّ StadiumBorder بمقاس "
    "72×40 وحشوة أفقية lg. وحُذف العنوان لا لإصلاح العطل بل لأن المرجع "
    "نفسه بلا عنوان: حبّة «اليوم» وسهم الرجوع فقط. ومفتاح "
    "fixturesCalendarPickTitle صار يتيمًا فحُذف من الملفات الخمسة على نمط "
    "25_remove_orphan_admin_l10n_keys — "
    "apps/mobile/lib/features/fixture_prediction/widgets/fixtures_calendar_page.dart, "
    "apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, "
    "apps/mobile/lib/l10n/app_localizations.dart, "
    "apps/mobile/lib/l10n/app_localizations_ar.dart, "
    "apps/mobile/lib/l10n/app_localizations_en.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = [
    "apps/mobile/lib/features/fixture_prediction/widgets/fixtures_calendar_page.dart",
    "apps/mobile/lib/l10n/app_ar.arb",
    "apps/mobile/lib/l10n/app_en.arb",
    "apps/mobile/lib/l10n/app_localizations.dart",
    "apps/mobile/lib/l10n/app_localizations_ar.dart",
    "apps/mobile/lib/l10n/app_localizations_en.dart",
    "docs/checkpoints/session-log.md",
]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "fix(mobile): calendar app bar swallowed by an oversized today button"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
