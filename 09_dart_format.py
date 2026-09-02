import datetime
import os
import pathlib
import subprocess
import sys

os.chdir(pathlib.Path(__file__).resolve().parent)

CHANGED_FILES = [
    "apps/server/lib/composition/composition_root.dart",
    "apps/server/test/routes/scoring_routes_test.dart",
]

print("==> [1/3] تطبيق dart format على الملفين المتأثرين")
result_fmt = subprocess.run(
    ["dart", "format"] + CHANGED_FILES,
    capture_output=True,
    text=True,
)
print(result_fmt.stdout + result_fmt.stderr)
if result_fmt.returncode != 0:
    print("فشل dart format نفسه — توقف")
    sys.exit(1)

print("==> [2/3] تحقق: dart format --set-exit-if-changed على كامل المستودع")
result_check = subprocess.run(
    ["dart", "format", "--output=none", "--set-exit-if-changed", "."],
    capture_output=True,
    text=True,
)
print(result_check.stdout + result_check.stderr)
ok = result_check.returncode == 0
test_status = (
    "نجح (dart format: لا تغييرات متبقية)"
    if ok
    else "فشل (لا تزال هناك ملفات غير منسَّقة خارج نطاق هذين الملفين)"
)
print("    النتيجة: " + test_status)

print("==> [3/3] session-log + commit (مسارات محددة، لا -A)")
now = datetime.datetime.now().strftime("%H:%M")
log_line = (
    "- [" + now + "] إصلاح: dart format على composition_root.dart وscoring_routes_test.dart "
    "(اختلاف تنسيق ناتج عن تعديلات str_replace المباشرة في سكربتي 05/06 وسكربتي 02/03) — "
    "اكتُشف عبر melos run verify → format-check؛ dart analyze لا يكشف اختلاف التنسيق "
    "(فراغات/أسطر)، شرط عبور format-check منفصل ولا يُغني عنه | ملف: "
    "apps/server/lib/composition/composition_root.dart، "
    "apps/server/test/routes/scoring_routes_test.dart | اختبار: " + test_status + "\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(
    ["git", "add"] + CHANGED_FILES + ["docs/checkpoints/session-log.md"],
    check=True,
)
subprocess.run(
    [
        "git",
        "commit",
        "-m",
        "style: dart format composition_root.dart and scoring_routes_test.dart",
    ],
    check=True,
)

print("")
print("تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
if not ok:
    sys.exit(1)
