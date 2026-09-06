#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""31_day_strip_centring — الشريط لم يكن يتوسّط اليوم المختار."""
import os, subprocess

ROOT = "/home/dev/nukhbaa-backup-1787537565"
if not os.path.isdir(ROOT):
    ROOT = os.getcwd()
M = os.path.join(ROOT, "apps/mobile")
assert os.path.isdir(M), "apps/mobile not found under %s" % ROOT

REL = "lib/features/fixture_prediction/widgets/fixtures_date_bar.dart"
P = os.path.join(M, REL)
with open(P, encoding="utf-8") as f:
    s = f.read()


def rep(old, new):
    global s
    assert s.count(old) == 1, "anchor x%d in %s" % (s.count(old), REL)
    s = s.replace(old, new, 1)


rep(
    """  final ScrollController _controller = ScrollController();
  final GlobalKey _selectedKey = GlobalKey();""",
    """  final ScrollController _controller = ScrollController();
  final GlobalKey _selectedKey = GlobalKey();

  /// The very first centring jumps rather than animates — animating from
  /// offset 0 on the first frame reads as the strip sliding away on its
  /// own before the user has touched anything.
  bool _centredOnce = false;""",
)

rep(
    """      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: AppMotion.fast,
        curve: AppMotion.standardCurve,
      );""",
    """      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: _centredOnce ? AppMotion.fast : Duration.zero,
        curve: AppMotion.standardCurve,
      );
      _centredOnce = true;""",
)

# الخلل: ListView.builder لا يبني إلا العناصر الظاهرة، والعنصر المختار
# (الفهرس 7) خارج الشاشة عند أول إطار، فـ_selectedKey.currentContext يعود
# null ولا يحدث أي توسيط — فيظهر الشريط عالقًا على أقدم يوم في النافذة بلا
# «اليوم» ولا خط تحديد. خمسة عشر عنصر نص لا تحتاج بناءً كسولًا أصلًا.
rep(
    """      child: ListView.builder(
        key: const Key('currentMonthFixtures.dayStrip'),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        itemCount: _radius * 2 + 1,
        itemBuilder: (context, index) {
          final DateTime day = selected.add(Duration(days: index - _radius));
          final bool isSelected = index == _radius;
          return _DayTab(
            key: isSelected ? _selectedKey : null,
            label: _label(context, day, today),
            selected: isSelected,
            tokens: tokens,
            onTap: () => widget.onDaySelected(day),
          );
        },
      ),""",
    """      child: SingleChildScrollView(
        key: const Key('currentMonthFixtures.dayStrip'),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            for (int index = 0; index < _radius * 2 + 1; index++)
              _DayTab(
                key: index == _radius ? _selectedKey : null,
                label: _label(
                  context,
                  selected.add(Duration(days: index - _radius)),
                  today,
                ),
                selected: index == _radius,
                tokens: tokens,
                onTap: () => widget.onDaySelected(
                  selected.add(Duration(days: index - _radius)),
                ),
              ),
          ],
        ),
      ),""",
)

with open(P, "w", encoding="utf-8") as f:
    f.write(s)
print("patched", REL)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 31_day_strip_centring: شريط الأيام كان يفتح عالقًا على "
    "أقدم يوم في نافذته (الأحد 30 أغسطس بينما اليوم 6 سبتمبر) بلا تسمية "
    "«اليوم» ولا خط تحديد. السبب: ListView.builder لا يبني إلا العناصر "
    "الظاهرة، والعنصر المختار في وسط النافذة (الفهرس 7) خارج الشاشة عند "
    "أول إطار، فـ_selectedKey.currentContext يعود null في addPostFrameCallback "
    "ولا يُنفَّذ Scrollable.ensureVisible أبدًا — عطل صامت لا يرمي شيئًا. "
    "استُبدل بـSingleChildScrollView + Row فتُبنى الخمسة عشر عنصرًا جميعًا "
    "(نصوص فقط، لا كلفة) ويجد المفتاح سياقه. وأُضيف _centredOnce: أول توسيط "
    "قفزة بلا حركة كي لا يبدو الشريط منزلقًا من تلقائه قبل أن يلمسه أحد، "
    "وما بعده متحرّك — "
    "apps/mobile/lib/features/fixture_prediction/widgets/fixtures_date_bar.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = [
    "apps/mobile/lib/features/fixture_prediction/widgets/fixtures_date_bar.dart",
    "docs/checkpoints/session-log.md",
]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "fix(mobile): day strip never centred on the selected day"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
