#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""29_card_metrics_parity — مقاسات البطاقة مقيسة من الصورة المرجعية."""
import os, subprocess

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


CARD = "lib/features/fixture_prediction/widgets/fotmob_match_card.dart"

# الشعار: قياس المرجع 91px عند 1080 (مقياس 2.75) ≈ 33 منطقية؛ الحالي 56.
patch(
    CARD,
    """  /// Local to this card so the shared `AppSizes.iconXl` token keeps its
  /// meaning for every other screen that reads it.
  static const double _crestSize = 56;""",
    """  /// Local to this card so the shared `AppSizes.iconXl` token keeps its
  /// meaning for every other screen that reads it. 34 is the reference's
  /// own crest, measured off the screenshot: 91px wide at a 1080px/2.75x
  /// capture. The previous 56 was ~65% larger and was what made the card
  /// read as crest-first rather than score-first.
  static const double _crestSize = 34;""",
)

# صندوق العدّاد: عرض المرجع 167px @1080 ≈ 61 منطقية (الحالي 68)، والارتفاع
# على نفس نسبة العرض 68:92.
patch(
    CARD,
    """  static const double _width = 68;
  static const double _height = 92;
  static const double _zoneHeight = 28;""",
    """  // Measured off the reference screenshot (1080px capture, 2.75x): the
  // stepper box is 167px wide there, i.e. 61 logical, not 68. Height and
  // tap-zone follow at the same ratio so the box keeps its proportions.
  static const double _width = 61;
  static const double _height = 82;
  static const double _zoneHeight = 26;""",
)

# هامش البطاقة الجانبي: المرجع 15px @1080 ≈ 6 منطقية؛ أقرب رمز هو sm=8.
patch(
    "lib/features/fixture_prediction/current_month_fixtures_screen.dart",
    "              padding: const EdgeInsets.all(AppSpacing.lg),",
    "              // The reference leaves ~6 logical px either side of the\n"
    "              // card (15px at 1080/2.75x); `lg` (16) was nearly triple\n"
    "              // that and visibly narrowed every card.\n"
    "              padding: const EdgeInsets.all(AppSpacing.sm),",
)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 29_card_metrics_parity: مقاسات البطاقة قيست فعليًا من "
    "لقطة المرجع (1080px، مقياس 2.75) وقورنت بلقطة التطبيق، فظهر أن التطابق "
    "كان مزعومًا لا مقيسًا. الشعار 91px في المرجع مقابل 152px في التطبيق "
    "(56 منطقية) فصار 34؛ صندوق العدّاد 167px مقابل 188px فصار العرض 61 "
    "والارتفاع 82 ومنطقة النقر 26 على نفس النسبة؛ الهامش الجانبي للبطاقة "
    "15px مقابل 45px فصار AppSpacing.sm بدل lg. لم تُمسّ الألوان: المرجع "
    "رمادي محايد (#2C303B للسطح، #383838 للعدّاد، خلفية سوداء تامة) بينما "
    "التطبيق بنفسجي (#181327 و#262233 وخلفية #07060E)، ومصدرها AppTokens "
    "لا البطاقة، فتغييرها يمسّ كل شاشة وينتظر قرار المالك — "
    "apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart, "
    "apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = [
    "apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart",
    "apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart",
    "docs/checkpoints/session-log.md",
]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "fix(mobile): match-card metrics measured against the reference capture"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
