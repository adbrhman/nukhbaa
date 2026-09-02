import os
import pathlib
import subprocess

os.chdir(pathlib.Path(__file__).resolve().parent)

CLASSES = [
    "ScoreRound",
    "ScoreRoundsForFixture",
    "GetRoundScores",
    "GetRoundReport",
    "AdminGetRoundScores",
    "AdminGetRoundReport",
    "PostRoundToLedger",
    "GetRoundLeaderboard",
]

TEST_FILES = [
    "packages/application/test/post_round_to_ledger_test.dart",
    "packages/application/test/get_round_scores_test.dart",
    "packages/application/test/score_round_test.dart",
]

print("==> [1/4] وجود ملف تعريف كل صنف داخل packages/application/lib")
class_to_file = {}
for cls in CLASSES:
    r = subprocess.run(
        ["grep", "-rl", "class " + cls, "packages/application/lib", "--include=*.dart"],
        capture_output=True,
        text=True,
    )
    files = [f for f in r.stdout.strip().splitlines() if f]
    class_to_file[cls] = files
    if files:
        print(cls + " -> موجود: " + ", ".join(files))
    else:
        print(cls + " -> غير موجود (محذوف بالفعل أو لم يكن له ملف مستقل)")

print("")
print("==> [2/4] أسطر التصدير في packages/application/lib/application.dart")
app_dart = pathlib.Path("packages/application/lib/application.dart")
app_content = app_dart.read_text(encoding="utf-8") if app_dart.exists() else ""
for cls in CLASSES:
    hits = [ln for ln in app_content.splitlines() if cls.lower() in ln.lower() or cls in ln]
    if hits:
        print(cls + " -> أسطر مرتبطة محتملة:")
        for h in hits:
            print("    " + h.strip())
    else:
        print(cls + " -> لا سطر تصدير باسمه في application.dart")

print("")
print("==> [3/4] استهلاك خارج packages/application (server + mobile)")
for cls in CLASSES:
    r = subprocess.run(
        ["grep", "-rln", cls, "apps/server", "apps/mobile", "--include=*.dart"],
        capture_output=True,
        text=True,
    )
    hits = [f for f in r.stdout.strip().splitlines() if f]
    if hits:
        print(cls + " -> مستهلَك في: " + ", ".join(hits))
    else:
        print(cls + " -> صفر مستهلكين في apps/server أو apps/mobile")

print("")
print("==> [4/4] ملفات الاختبار الثلاثة المخصصة لـRound")
for tf in TEST_FILES:
    exists = pathlib.Path(tf).exists()
    print(tf + " -> " + ("موجود" if exists else "غير موجود (محذوف بالفعل)"))

print("")
print("==> dart analyze packages/application (تأكيد نهائي)")
analyze = subprocess.run(
    ["dart", "analyze", "packages/application"],
    capture_output=True,
    text=True,
)
print(analyze.stdout + analyze.stderr)
