import datetime
import os
import pathlib
import re
import shutil
import subprocess
import sys

os.chdir(pathlib.Path(__file__).resolve().parent)
root = pathlib.Path(".")

FILES_TO_DELETE = [
    root / "apps/server/test/routes/round_predictions_test.dart",
    root / "apps/server/test/routes/rounds_browse_test.dart",
]
LEDGER = root / "apps/server/test/routes/ledger_routes_test.dart"
SCORING = root / "apps/server/test/routes/scoring_routes_test.dart"


def remove_group_block(text: str, title_marker: str) -> str:
    idx = text.index(title_marker)
    line_start = text.rfind("\n", 0, idx) + 1
    prev_nl = line_start - 1
    if prev_nl >= 0:
        prev_line_start = text.rfind("\n", 0, prev_nl) + 1
        prev_line = text[prev_line_start:prev_nl]
        if prev_line.strip() and set(prev_line.strip()) == {"-"}:
            line_start = prev_line_start
    group_open = text.index("group(", idx)
    close_pat = re.compile(r"\n {2}\}\);\n")
    m = close_pat.search(text, group_open)
    if not m:
        raise RuntimeError("تعذر إيجاد إغلاق المجموعة (نمط '  });') بعد: " + repr(title_marker))
    end = m.end()
    if text[end : end + 1] == "\n":
        end += 1
    return text[:line_start] + text[end:]


def remove_import(text: str, import_line: str) -> str:
    count = text.count(import_line)
    if count != 1:
        raise RuntimeError(f"سطر الاستيراد غير فريد ({count}x): {import_line!r}")
    return text.replace(import_line, "", 1)


ledger_text = LEDGER.read_text(encoding="utf-8")
ledger_text = remove_import(
    ledger_text,
    "import '../../routes/rounds/[id]/ledger/index.dart' as post_ledger_route;\n",
)
ledger_text = remove_group_block(
    ledger_text,
    "// POST /rounds/{id}/ledger — PostRoundToLedger (admin-only command)",
)

scoring_text = SCORING.read_text(encoding="utf-8")
scoring_text = remove_import(
    scoring_text,
    "import '../../routes/rounds/[id]/score/index.dart' as score_route;\n",
)
scoring_text = remove_import(
    scoring_text,
    "import '../../routes/rounds/[id]/scores/index.dart' as scores_route;\n",
)
scoring_text = remove_group_block(
    scoring_text,
    "// POST /rounds/{id}/score — ScoreRound (admin-only command)",
)
scoring_text = remove_group_block(
    scoring_text,
    "// GET /rounds/{id}/scores — GetRoundScores (participant read, scored-gated)",
)

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
backup_dir = pathlib.Path.home() / "nukhbaa-round-backups" / f"server_tests_{ts}"
backup_dir.mkdir(parents=True, exist_ok=True)
for p in FILES_TO_DELETE + [LEDGER, SCORING]:
    shutil.copy2(p, backup_dir / p.name)
print(f"==> [1/4] نسخة احتياطية في {backup_dir}")

print("==> [2/4] حذف/تعديل ملفات الاختبار")
for p in FILES_TO_DELETE:
    p.unlink()
    print(f"    حُذف: {p}")
LEDGER.write_text(ledger_text, encoding="utf-8")
print(f"    عُدّل: {LEDGER}")
SCORING.write_text(scoring_text, encoding="utf-8")
print(f"    عُدّل: {SCORING}")

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
test_status = "نجح (dart analyze: لا أخطاء)" if ok else f"فشل (راجع {analyze_log})"
print(f"    النتيجة: {test_status}")
print("--- آخر 80 سطر من مخرجات dart analyze ---")
print("\n".join((result.stdout + result.stderr).splitlines()[-80:]))

print("==> [4/4] session-log + commit")
now = datetime.datetime.now().strftime("%H:%M")
log_line = (
    f"- [{now}] حذف/تعديل: حذف round_predictions_test.dart وrounds_browse_test.dart بالكامل "
    f"(مستهلكان لروتات Round المحذوفة في السكربت 01)، وتنظيف مجموعتي اختبار Round من "
    f"ledger_routes_test.dart (POST /rounds/{{id}}/ledger) وscoring_routes_test.dart "
    f"(POST /rounds/{{id}}/score، GET /rounds/{{id}}/scores) مع استيراداتها اليتيمة | "
    f"ملف: apps/server/test/routes/round_predictions_test.dart(محذوف), "
    f"apps/server/test/routes/rounds_browse_test.dart(محذوف), "
    f"apps/server/test/routes/ledger_routes_test.dart, "
    f"apps/server/test/routes/scoring_routes_test.dart | اختبار: {test_status}\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(
    ["git", "commit", "-m", "test(server): remove Round-only test files/blocks after routes deletion"],
    check=True,
)

print("\n✅ تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
if not ok:
    sys.exit(1)
