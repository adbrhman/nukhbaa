#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""30_neutral_dark_palette — أساس داكن محايد بقياسات المرجع بدل البنفسجي."""
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


C = "lib/core/theme/app_colors.dart"

patch(
    C,
    """/// Dark palette — ELITE OBSIDIAN V1.0 design system (violet action + gold
/// achievement, on an Obsidian dark foundation).
abstract final class AppColors {
  static const Color background = Color(0xFF07050D);
  static const Color backgroundElevated = Color(0xFF0A0811);
  static const Color surface = Color(0xFF181326);
  static const Color surfaceElevated = Color(0xFF1D1730);
  static const Color surfaceHigh = Color(0xFF241C3A);""",
    """/// Dark palette — ELITE OBSIDIAN V1.0 accents (blue action + gold
/// achievement) on a **neutral** dark foundation.
///
/// The neutral values below are not chosen by eye: they are sampled from the
/// reference capture the matches screen is being matched against — pure
/// black page, `#2F2F2F` card, `#383838` raised control. The violet
/// foundation this replaces (`#07050D` / `#181326` / `#1D1730` / `#241C3A`)
/// tinted every surface in the app and was the single largest visual gap
/// left after the metric pass (`29_card_metrics_parity`). Accent, semantic
/// and achievement colors are deliberately untouched — only the neutral
/// ramp and the two grey text tones move, so the app keeps its identity.
abstract final class AppColors {
  static const Color background = Color(0xFF000000);
  static const Color backgroundElevated = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF2F2F2F);
  static const Color surfaceElevated = Color(0xFF383838);
  static const Color surfaceHigh = Color(0xFF424242);""",
)

patch(
    C,
    """  static const Color textSecondary = Color(0xFFC8C2D3);
  static const Color textMuted = Color(0xFF6F687D);""",
    """  // Sampled from the same capture: secondary label text reads near-white,
  // muted label text ~#9D9D9D. The violet-tinted greys they replace read
  // markedly darker and cooler against the new neutral surfaces.
  static const Color textSecondary = Color(0xFFE3E3E3);
  static const Color textMuted = Color(0xFF9D9D9D);""",
)

LOG = os.path.join(ROOT, "docs/checkpoints/session-log.md")
entry = (
    "\n2026-09-06 — 30_neutral_dark_palette: الأساس الداكن في AppColors صار "
    "محايدًا بقيم مأخوذة عيّنةً من لقطة المرجع لا بالتقدير: الخلفية "
    "#000000 والسطح #2F2F2F والمرتفع #383838 والأعلى #424242، والنصّان "
    "الثانوي والخافت #E3E3E3 و#9D9D9D. البنفسجي المستبدَل "
    "(#07050D/#181326/#1D1730/#241C3A) كان يصبغ كل سطح في التطبيق وكان "
    "أكبر فجوة بصرية بقيت بعد 29_card_metrics_parity. لم تُمسّ ألوان "
    "الإجراء (primary) ولا الإنجاز (gold/silver/bronze) ولا الدلالات "
    "(success/warning/info/error) ولا لوحة الوضع الفاتح، فالتغيير سلّم "
    "رمادي فقط. تحقّق قبل التعديل: لا سطر في lib أو test يذكر أيًّا من "
    "الرموز الستّة القديمة خارج app_colors.dart، فلا مرجع مكسور. أثره "
    "يتجاوز شاشة المباريات إلى كل شاشة تقرأ AppTokens — بقرار المالك "
    "«نفس تطبيق فيت موب» — "
    "apps/mobile/lib/core/theme/app_colors.dart\n"
)
with open(LOG, "a", encoding="utf-8") as f:
    f.write(entry)
print("session log appended")

files = ["apps/mobile/lib/core/theme/app_colors.dart", "docs/checkpoints/session-log.md"]
if os.path.isdir(os.path.join(ROOT, ".git")):
    subprocess.run(["git", "-C", ROOT, "add"] + files, check=True)
    subprocess.run(
        ["git", "-C", ROOT, "commit", "-m",
         "style(mobile): neutral dark foundation sampled from the reference capture"],
        check=True,
    )
    print("committed (no push)")
else:
    print("no .git — skipped commit")
