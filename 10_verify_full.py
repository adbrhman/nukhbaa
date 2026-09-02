import datetime
import os
import pathlib
import subprocess

os.chdir(pathlib.Path(__file__).resolve().parent)

print("==> melos run verify (format-check + analyze + import-lint + test + test-mobile)")
result = subprocess.run(
    ["dart", "run", "melos", "run", "verify"],
    capture_output=True,
    text=True,
)
print(result.stdout[-6000:] + result.stderr[-3000:])
ok = result.returncode == 0
test_status = "نجح بالكامل" if ok else "فشل — راجع الأخطاء أعلاه"
print("")
print("النتيجة: " + test_status)

now = datetime.datetime.now().strftime("%H:%M")
log_line = (
    "- [" + now + "] تحقق: melos run verify شامل بعد استعادة fakes.dart وإصلاح format "
    "(e9b9bb6, d8533c4) | اختبار: " + test_status + "\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(["git", "add", "docs/checkpoints/session-log.md"], check=True)
subprocess.run(
    ["git", "commit", "-m", "chore: log full verify result"],
    check=True,
)

print("")
print("تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
