import os
import pathlib
import subprocess

os.chdir(pathlib.Path(__file__).resolve().parent)

FILES_TO_CHECK = [
    "apps/server/lib/composition/composition_root.dart",
    "apps/server/routes/fixtures/[id]/result/index.dart",
    "apps/server/routes/fixtures/[id]/score/index.dart",
    "apps/server/test/routes/competition_route_harness.dart",
    "apps/mobile/lib/features/admin/admin_providers.dart",
    "apps/mobile/lib/features/admin/admin_providers.g.dart",
    "apps/mobile/lib/l10n/app_localizations.dart",
    "apps/mobile/lib/l10n/app_localizations_ar.dart",
    "apps/mobile/lib/l10n/app_localizations_en.dart",
    "apps/mobile/test/features/admin/score_fixture_controller_test.dart",
    "apps/server/lib/http/ledger_dto_mapper.dart",
    "apps/server/test/routes/ledger_routes_test.dart",
]

print("==> سياق كل مطابقة لـ'ScoreRound' بحدود كلمة دقيقة (grep -nw)")
for f in FILES_TO_CHECK:
    p = pathlib.Path(f)
    if not p.exists():
        print(f + " -> الملف غير موجود")
        continue
    r = subprocess.run(
        ["grep", "-nE", r"\bScoreRound\b"],
        input=p.read_text(encoding="utf-8", errors="replace"),
        capture_output=True,
        text=True,
    )
    lines = r.stdout.strip().splitlines()
    if lines:
        print("=== " + f + " ===")
        for ln in lines:
            print("    " + ln.strip()[:200])
    else:
        print(f + " -> لا مطابقة بحدود كلمة دقيقة (كانت ضوضاء نصية فقط)")

print("")
print("==> نفس التحقق لـ'PostRoundToLedger' (بحدود كلمة)")
for f in [
    "apps/server/lib/composition/composition_root.dart",
    "apps/server/lib/http/ledger_dto_mapper.dart",
    "apps/server/test/routes/ledger_routes_test.dart",
    "apps/mobile/test/features/admin/score_fixture_controller_test.dart",
]:
    p = pathlib.Path(f)
    if not p.exists():
        continue
    r = subprocess.run(
        ["grep", "-nE", r"\bPostRoundToLedger\b"],
        input=p.read_text(encoding="utf-8", errors="replace"),
        capture_output=True,
        text=True,
    )
    lines = r.stdout.strip().splitlines()
    if lines:
        print("=== " + f + " ===")
        for ln in lines:
            print("    " + ln.strip()[:200])
    else:
        print(f + " -> لا مطابقة بحدود كلمة دقيقة")

print("")
print("==> نفس التحقق لـ'GetRoundScores' و'AdminGetRoundScores' في composition_root.dart")
p = pathlib.Path("apps/server/lib/composition/composition_root.dart")
if p.exists():
    content = p.read_text(encoding="utf-8", errors="replace")
    for cls in ["GetRoundScores", "AdminGetRoundScores"]:
        r = subprocess.run(
            ["grep", "-nE", r"\b" + cls + r"\b"],
            input=content,
            capture_output=True,
            text=True,
        )
        lines = r.stdout.strip().splitlines()
        if lines:
            print("=== " + cls + " ===")
            for ln in lines:
                print("    " + ln.strip()[:200])
        else:
            print(cls + " -> لا مطابقة بحدود كلمة دقيقة")
