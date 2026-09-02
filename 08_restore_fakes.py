import datetime
import os
import pathlib
import subprocess
import sys

os.chdir(pathlib.Path(__file__).resolve().parent)

FAKES_PATH = "packages/application/test/scoring/fakes.dart"
DELETION_COMMIT = "a002dcd"

print("==> [1/4] التحقق من وجود الكوميت المتهم بالحذف")
r = subprocess.run(["git", "cat-file", "-e", DELETION_COMMIT], capture_output=True)
if r.returncode != 0:
    print("الكوميت " + DELETION_COMMIT + " غير موجود في هذا المستودع — توقف بلا تنفيذ.")
    sys.exit(1)

fakes_file = pathlib.Path(FAKES_PATH)
if fakes_file.exists():
    print("الملف موجود بالفعل — تخطي الاستعادة، الانتقال مباشرة للتحقق.")
else:
    print("==> [2/4] استعادة الملف من " + DELETION_COMMIT + "~1 (الحالة قبل الحذف)")
    show = subprocess.run(
        ["git", "show", DELETION_COMMIT + "~1:" + FAKES_PATH],
        capture_output=True,
        text=True,
    )
    if show.returncode != 0:
        print("فشل جلب المحتوى من git show — توقف بلا تنفيذ.")
        print(show.stderr)
        sys.exit(1)
    fakes_file.parent.mkdir(parents=True, exist_ok=True)
    fakes_file.write_text(show.stdout, encoding="utf-8")
    print("تمت الاستعادة: " + FAKES_PATH)

print("==> [3/4] dart analyze packages/application")
analyze = subprocess.run(
    ["dart", "analyze", "packages/application"],
    capture_output=True,
    text=True,
)
print(analyze.stdout + analyze.stderr)
ok = analyze.returncode == 0
test_status = "نجح (No issues found)" if ok else "فشل (لا يزال هناك أخطاء)"
print("    النتيجة: " + test_status)

if not ok:
    print("")
    print("توقف فوري: dart analyze لم ينجح — لا commit. راجع الأخطاء أعلاه.")
    sys.exit(1)

print("==> [4/4] session-log + commit (مسارات محددة، لا -A)")
now = datetime.datetime.now().strftime("%H:%M")
log_line = (
    "- [" + now + "] إصلاح: استعادة " + FAKES_PATH + " المحذوف خطأً في سكربت 07 (" + DELETION_COMMIT + ") "
    "— كان لا يزال مستهلَكًا من get_fixture_scores_test.dart وrecord_fixture_result_test.dart "
    "وscore_fixture_test.dart عبر استيراد نسبي مباشر لم يلتقطه التحقق السابق | ملف: " + FAKES_PATH +
    " | اختبار: dart analyze packages/application → " + test_status + "\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(
    ["git", "add", FAKES_PATH, "docs/checkpoints/session-log.md"],
    check=True,
)
subprocess.run(
    ["git", "commit", "-m", "fix: restore accidentally deleted scoring/fakes.dart"],
    check=True,
)

print("")
print("تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
