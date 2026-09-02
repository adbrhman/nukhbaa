import datetime
import os
import pathlib
import shutil
import subprocess
import sys

os.chdir(pathlib.Path(__file__).resolve().parent)
root = pathlib.Path(".")

LEDGER = root / "apps/server/test/routes/ledger_routes_test.dart"
SCORING = root / "apps/server/test/routes/scoring_routes_test.dart"


def remove_line(text: str, exact_line: str) -> str:
    count = text.count(exact_line)
    if count != 1:
        raise RuntimeError(f"سطر غير فريد ({count}x): {exact_line!r}")
    return text.replace(exact_line, "", 1)


def remove_decl(text: str, signature_marker: str) -> str:
    idx = text.index(signature_marker)
    line_start = text.rfind("\n", 0, idx) + 1
    while True:
        prev_nl = line_start - 1
        if prev_nl < 0:
            break
        prev_line_start = text.rfind("\n", 0, prev_nl) + 1
        prev_line = text[prev_line_start:prev_nl]
        stripped = prev_line.strip()
        if stripped.startswith("///") or (stripped and set(stripped) == {"-"}):
            line_start = prev_line_start
            continue
        break
    arrow_idx = text.index("=>", idx)
    open_paren = text.index("(", arrow_idx)
    depth = 0
    i = open_paren
    while True:
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    close_paren = i
    semi = text.index(";", close_paren)
    end = semi + 1
    if text[end : end + 1] == "\n":
        end += 1
    if text[end : end + 1] == "\n":
        end += 1
    return text[:line_start] + text[end:]


ledger_text = LEDGER.read_text(encoding="utf-8")
ledger_text = remove_line(
    ledger_text,
    "  const kFixtureId = '66666666-6666-6666-6666-666666666666';\n",
)

scoring_text = SCORING.read_text(encoding="utf-8")
scoring_text = remove_line(
    scoring_text,
    "  final roundId = (RoundId.tryParse(kRoundId) as Ok<RoundId>).value;\n",
)
scoring_text = remove_decl(scoring_text, "RulesetSnapshot snapshot()")

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
backup_dir = pathlib.Path.home() / "nukhbaa-round-backups" / f"server_test_helpers2_{ts}"
backup_dir.mkdir(parents=True, exist_ok=True)
for p in [LEDGER, SCORING]:
    shutil.copy2(p, backup_dir / p.name)
print(f"==> [1/4] نسخة احتياطية في {backup_dir}")

print("==> [2/4] كتابة الملفين المعدَّلين")
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
    f"- [{now}] تنظيف: حذف عناصر يتيمة تسلسلية بعد السكربت 03 — "
    f"ledger_routes_test.dart: kFixtureId؛ scoring_routes_test.dart: roundId/snapshot | "
    f"ملف: apps/server/test/routes/ledger_routes_test.dart, "
    f"apps/server/test/routes/scoring_routes_test.dart | اختبار: {test_status}\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(
    [
        "git",
        "commit",
        "-m",
        "test(server): remove cascaded-unused Round test helpers (round 2)",
    ],
    check=True,
)

print("\n✅ تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
if not ok:
    sys.exit(1)
