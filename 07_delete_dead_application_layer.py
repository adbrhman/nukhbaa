import datetime
import os
import pathlib
import shutil
import subprocess
import sys

os.chdir(pathlib.Path(__file__).resolve().parent)
root = pathlib.Path(".")

LIB_FILES = [
    root / "packages/application/lib/src/leaderboard/get_round_leaderboard.dart",
    root / "packages/application/lib/src/ledger/post_round_to_ledger.dart",
    root / "packages/application/lib/src/scoring/get_round_scores.dart",
    root / "packages/application/lib/src/scoring/score_round.dart",
    root / "packages/application/lib/src/scoring/admin_get_round_report.dart",
    root / "packages/application/lib/src/scoring/admin_get_round_scores.dart",
    root / "packages/application/lib/src/scoring/get_round_report.dart",
    root / "packages/application/lib/src/scoring/score_rounds_for_fixture.dart",
]

TEST_FILES = [
    root / "packages/application/test/ledger/post_round_to_ledger_test.dart",
    root / "packages/application/test/scoring/get_round_scores_test.dart",
    root / "packages/application/test/scoring/score_round_test.dart",
    root / "packages/application/test/scoring/fakes.dart",
]

BARREL = root / "packages/application/lib/application.dart"

EXPORT_LINES = [
    "export 'src/leaderboard/get_round_leaderboard.dart';\n",
    "export 'src/ledger/post_round_to_ledger.dart';\n",
    "export 'src/scoring/admin_get_round_report.dart';\n",
    "export 'src/scoring/admin_get_round_scores.dart';\n",
    "export 'src/scoring/get_round_report.dart';\n",
    "export 'src/scoring/get_round_scores.dart';\n",
    "export 'src/scoring/score_round.dart';\n",
    "export 'src/scoring/score_rounds_for_fixture.dart';\n",
]


def remove_exact_line(text, exact_line):
    count = text.count(exact_line)
    if count != 1:
        raise RuntimeError("سطر غير فريد (" + str(count) + "x): " + repr(exact_line))
    return text.replace(exact_line, "", 1)


ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
backup_dir = pathlib.Path.home() / "nukhbaa-round-backups" / ("application_layer_" + ts)
backup_dir.mkdir(parents=True, exist_ok=True)

print("==> [1/4] نسخة احتياطية في " + str(backup_dir))
for p in LIB_FILES + TEST_FILES + [BARREL]:
    dest = backup_dir / (str(p).replace("/", "__"))
    shutil.copy2(p, dest)

print("==> [2/4] حذف الملفات (8 مصدر + 4 اختبار/fakes) وتعديل application.dart")
for p in LIB_FILES + TEST_FILES:
    p.unlink()
    print("    حُذف: " + str(p))

barrel_text = BARREL.read_text(encoding="utf-8")
for line in EXPORT_LINES:
    barrel_text = remove_exact_line(barrel_text, line)
BARREL.write_text(barrel_text, encoding="utf-8")
print("    عُدّل: " + str(BARREL) + " (8 أسطر تصدير محذوفة)")

print("==> [3/4] تحقق تركيبي (dart analyze packages/application)")
analyze_log = backup_dir / "analyze_output.log"
result = subprocess.run(
    ["dart", "analyze", "--fatal-warnings", "."],
    cwd="packages/application",
    capture_output=True,
    text=True,
)
analyze_log.write_text(result.stdout + result.stderr, encoding="utf-8")
ok = result.returncode == 0
test_status = "نجح (dart analyze: لا أخطاء)" if ok else ("فشل (راجع " + str(analyze_log) + ")")
print("    النتيجة: " + test_status)
print("--- آخر 80 سطر من مخرجات dart analyze ---")
print("\n".join((result.stdout + result.stderr).splitlines()[-80:]))

print("==> [4/4] session-log + commit")
now = datetime.datetime.now().strftime("%H:%M")
log_line = (
    "- [" + now + "] حذف: الطبقة المصدرية الكاملة للثمانية use-cases الميتة "
    "(ScoreRound، ScoreRoundsForFixture، GetRoundScores، GetRoundReport، "
    "AdminGetRoundScores، AdminGetRoundReport، PostRoundToLedger، "
    "GetRoundLeaderboard) من packages/application/lib/src، مع اختباراتها الثلاثة "
    "(post_round_to_ledger_test.dart، get_round_scores_test.dart، "
    "score_round_test.dart) وملف scoring/fakes.dart اليتيم (صفر مستهلكين بعد حذف "
    "الثلاثة)، وإزالة أسطر التصدير الثمانية من application.dart | ملف: "
    "packages/application/lib/src/** (8 ملفات، محذوفة)، "
    "packages/application/test/** (4 ملفات، محذوفة)، "
    "packages/application/lib/application.dart | اختبار: " + test_status + "\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(
    [
        "git",
        "commit",
        "-m",
        "chore(application): delete 8 dead Round use-cases and their tests",
    ],
    check=True,
)

print("")
print("تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
if not ok:
    sys.exit(1)
