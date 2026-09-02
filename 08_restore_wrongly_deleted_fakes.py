import datetime
import os
import pathlib
import shutil
import subprocess
import sys

os.chdir(pathlib.Path(__file__).resolve().parent)
root = pathlib.Path(".")

BACKUP_SOURCE = (
    pathlib.Path.home()
    / "nukhbaa-round-backups"
    / "application_layer_20260902_014654"
    / "packages__application__test__scoring__fakes.dart"
)
TARGET = root / "packages/application/test/scoring/fakes.dart"

if not BACKUP_SOURCE.is_file():
    print("خطأ: النسخة الاحتياطية غير موجودة في المسار المتوقع: " + str(BACKUP_SOURCE))
    sys.exit(1)

if TARGET.exists():
    print("خطأ: " + str(TARGET) + " موجود بالفعل — لن يُستبدَل تلقائيًا")
    sys.exit(1)

print("==> [1/3] استعادة الملف من النسخة الاحتياطية")
shutil.copy2(BACKUP_SOURCE, TARGET)
print("    أُعيد: " + str(TARGET))

print("==> [2/3] تحقق تركيبي (dart analyze packages/application)")
backup_dir = BACKUP_SOURCE.parent
analyze_log = backup_dir / "analyze_output_fix.log"
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

print("==> [3/3] session-log + commit")
now = datetime.datetime.now().strftime("%H:%M")
log_line = (
    "- [" + now + "] إصلاح: استعادة packages/application/test/scoring/fakes.dart "
    "الذي حُذف بالخطأ في السكربت 07 — لا يزال مستهلَكًا فعليًا من "
    "get_fixture_scores_test.dart وrecord_fixture_result_test.dart وscore_fixture_test.dart "
    "(FakeFixtureResultRepository، scoringParticipant، scoringSnapshot)؛ خطأ التحقق "
    "السابق كان اقتصار البحث على الاستيراد النسبي من خارج المجلد "
    "('scoring/fakes.dart') فقط، فلم يلتقط الاستيراد النسبي المباشر من داخل نفس "
    "المجلد ('fakes.dart') في هذه الملفات الثلاثة؛ تقليم الأجزاء المخصصة لـRound "
    "فعليًا داخل الملف (إن وُجدت) مؤجَّل لفحص منفصل لاحق | ملف: "
    "packages/application/test/scoring/fakes.dart | اختبار: " + test_status + "\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(
    [
        "git",
        "commit",
        "-m",
        "fix(application): restore wrongly-deleted scoring/fakes.dart (still used by fixture tests)",
    ],
    check=True,
)

print("")
print("تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
if not ok:
    sys.exit(1)
