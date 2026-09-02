import datetime
import os
import pathlib
import shutil
import subprocess
import sys

os.chdir(pathlib.Path(__file__).resolve().parent)
root = pathlib.Path(".")

TARGET = root / "apps/server/lib/composition/composition_root.dart"


def remove_line_containing(text, marker):
    idx = text.index(marker)
    line_start = text.rfind("\n", 0, idx) + 1
    line_end = text.index("\n", idx) + 1
    return text[:line_start] + text[line_end:]


def remove_static_field(text, marker):
    idx = text.index(marker)
    line_start = text.rfind("\n", 0, idx) + 1
    semi = text.index(";", idx)
    end = semi + 1
    if text[end:end + 1] == "\n":
        end += 1
    return text[:line_start] + text[end:]


def remove_class_block(text, doc_marker, class_open_marker):
    doc_idx = text.index(doc_marker)
    line_start = text.rfind("\n", 0, doc_idx) + 1
    open_idx = text.index(class_open_marker)
    brace_idx = text.index("{", open_idx)
    depth = 0
    i = brace_idx
    while True:
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    end = i + 1
    if text[end:end + 1] == "\n":
        end += 1
    if text[end:end + 1] == "\n":
        end += 1
    return text[:line_start] + text[end:]


def replace_unique(text, old, new):
    count = text.count(old)
    if count != 1:
        raise RuntimeError("نص غير فريد (" + str(count) + "x): " + repr(old))
    return text.replace(old, new, 1)


text = TARGET.read_text(encoding="utf-8")

# 1) حذف الحقل الساكن _unwiredScoreRepository (لم يعد له أي استهلاك بعد سكربت 05)
text = remove_static_field(
    text, "static final ScoreRepository _unwiredScoreRepository ="
)

# 2) حذف كلاس _UnwiredScoreRepository بالكامل مع تعليقه التوثيقي
#    (أصبح ميتًا فور حذف الحقل أعلاه؛ لا مستهلك آخر له في الملف)
text = remove_class_block(
    text,
    doc_marker='/// Backs every "absent" scoring use-case\'s score port:',
    class_open_marker="final class _UnwiredScoreRepository implements ScoreRepository {",
)

# 3) حذف المتغير المحلي غير المستخدم داخل دالة التهيئة الفعلية
text = remove_line_containing(
    text, "final scoreRepository = PostgresScoreRepository(connection);"
)

# 4) تصحيح تعليق متدلٍّ كان يشير إلى scoreRepository (المحذوف في الخطوة 3)
#    fixtureScoreRepository نفسه لا يزال حيًا ومُستخدمًا — لا يُحذف السطر، يُصحَّح فقط
old_comment = (
    "    // Axiom 4 Amendment: the per-fixture Scoring context, its own\n"
    "    // Postgres-backed repository (kept separate, same reasoning as\n"
    "    // scoreRepository above).\n"
)
new_comment = (
    "    // Axiom 4 Amendment: the per-fixture Scoring context, its own\n"
    "    // Postgres-backed repository.\n"
)
text = replace_unique(text, old_comment, new_comment)

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
backup_dir = pathlib.Path.home() / "nukhbaa-round-backups" / ("composition_root2_" + ts)
backup_dir.mkdir(parents=True, exist_ok=True)
shutil.copy2(TARGET, backup_dir / TARGET.name)
print("==> [1/4] نسخة احتياطية في " + str(backup_dir))

print("==> [2/4] كتابة composition_root.dart المعدَّل")
TARGET.write_text(text, encoding="utf-8")
print("    عُدّل: " + str(TARGET))

print("==> [3/4] تحقق تركيبي (dart analyze apps/server)")
analyze_log = backup_dir / "analyze_output.log"
result = subprocess.run(
    ["dart", "analyze", "--fatal-warnings", "."],
    cwd="apps/server",
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
    "- [" + now + "] تنظيف: إزالة بقايا يتيمة من سكربت 05 في composition_root.dart — "
    "حذف حقل _unwiredScoreRepository وكلاس _UnwiredScoreRepository بالكامل "
    "(صفر مستهلكين بعد إلغاء ربط الثمانية)، حذف متغير scoreRepository المحلي غير "
    "المستخدم، وتصحيح تعليق متدلٍّ كان يشير إليه فوق fixtureScoreRepository | "
    "ملف: apps/server/lib/composition/composition_root.dart | اختبار: " + test_status + "\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(
    [
        "git",
        "commit",
        "-m",
        "chore(server): remove orphaned score-repository leftovers from composition_root",
    ],
    check=True,
)

print("")
print("تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
if not ok:
    sys.exit(1)
