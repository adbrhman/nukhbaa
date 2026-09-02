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


def remove_decl(text, signature_marker):
    idx = text.index(signature_marker)
    line_start = text.rfind("\n", 0, idx) + 1
    while True:
        prev_nl = line_start - 1
        if prev_nl < 0:
            break
        prev_line_start = text.rfind("\n", 0, prev_nl) + 1
        prev_line = text[prev_line_start:prev_nl]
        stripped = prev_line.strip()
        if stripped.startswith("///"):
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
    end = close_paren + 1
    while text[end] in " \t":
        end += 1
    if text[end] != ";":
        raise RuntimeError("لم يُعثر على ';' بعد إغلاق القوس لتصريح: " + repr(signature_marker))
    end += 1
    if text[end:end + 1] == "\n":
        end += 1
    if text[end:end + 1] == "\n":
        end += 1
    return text[:line_start] + text[end:]


def remove_field(text, field_marker):
    idx = text.index(field_marker)
    line_start = text.rfind("\n", 0, idx) + 1
    while True:
        prev_nl = line_start - 1
        if prev_nl < 0:
            break
        prev_line_start = text.rfind("\n", 0, prev_nl) + 1
        prev_line = text[prev_line_start:prev_nl]
        stripped = prev_line.strip()
        if stripped.startswith("///"):
            line_start = prev_line_start
            continue
        break
    end = idx + len(field_marker)
    if text[end:end + 1] == "\n":
        end += 1
    if text[end:end + 1] == "\n":
        end += 1
    return text[:line_start] + text[end:]


def remove_named_arg(text, marker):
    idx = text.index(marker)
    line_start = text.rfind("\n", 0, idx) + 1
    open_paren = idx + len(marker) - 1
    if text[open_paren] != "(":
        raise RuntimeError("marker يجب أن ينتهي بـ '(': " + repr(marker))
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
    end = close_paren + 1
    if text[end:end + 1] == ",":
        end += 1
    if text[end:end + 1] == "\n":
        end += 1
    return text[:line_start] + text[end:]


def remove_initializer(text, tail_marker):
    idx = text.index(tail_marker)
    prev_comma_nl = text.rfind(",\n", 0, idx)
    if prev_comma_nl == -1:
        raise RuntimeError("تعذر إيجاد بداية العنصر قبل: " + repr(tail_marker))
    entry_start = prev_comma_nl + 2
    end = idx + len(tail_marker)
    if text[end:end + 1] == "\n":
        end += 1
    return text[:entry_start] + text[end:]


def remove_doc_block_before(text, doc_start_marker, next_marker):
    start_idx = text.index(doc_start_marker)
    line_start = text.rfind("\n", 0, start_idx) + 1
    next_idx = text.index(next_marker)
    next_line_start = text.rfind("\n", 0, next_idx) + 1
    return text[:line_start] + text[next_line_start:]


def fix_bracket_ref(text, old, new):
    count = text.count(old)
    if count != 1:
        raise RuntimeError("مرجع غير فريد (" + str(count) + "x): " + repr(old))
    return text.replace(old, new, 1)


text = TARGET.read_text(encoding="utf-8")

# --- Section D: دوال _absentX (أولًا — يحل تصادم استدعاء _absentScoreRound()
# الداخلي داخل جسم _absentScoreRoundsForFixture قبل معالجة قائمة التهيئة) ---
text = remove_decl(text, "static ScoreRound _absentScoreRound()")
text = remove_decl(text, "static ScoreRoundsForFixture _absentScoreRoundsForFixture()")
text = remove_decl(text, "static GetRoundScores _absentGetRoundScores()")
text = remove_decl(text, "static GetRoundReport _absentGetRoundReport()")
text = remove_decl(text, "static AdminGetRoundScores _absentAdminGetRoundScores()")
text = remove_decl(text, "static AdminGetRoundReport _absentAdminGetRoundReport()")
text = remove_decl(text, "static PostRoundToLedger _absentPostRoundToLedger()")
text = remove_decl(text, "static GetRoundLeaderboard _absentGetRoundLeaderboard()")

# --- Section C: قائمة التهيئة (initializer list) ---
text = remove_initializer(text, "?? _absentScoreRound(),")
text = remove_initializer(text, "?? _absentScoreRoundsForFixture(),")
text = remove_initializer(text, "?? _absentGetRoundScores(),")
text = remove_initializer(text, "?? _absentGetRoundReport(),")
text = remove_initializer(text, "?? _absentAdminGetRoundScores(),")
text = remove_initializer(text, "?? _absentAdminGetRoundReport(),")
text = remove_initializer(text, "?? _absentPostRoundToLedger(),")
text = remove_initializer(text, "?? _absentGetRoundLeaderboard(),")

# --- Section A: معاملات required this.X ---
text = remove_line_containing(text, "required this.scoreRound,")
text = remove_line_containing(text, "required this.scoreRoundsForFixture,")
text = remove_line_containing(text, "required this.getRoundScores,")
text = remove_line_containing(text, "required this.getRoundReport,")
text = remove_line_containing(text, "required this.adminGetRoundScores,")
text = remove_line_containing(text, "required this.adminGetRoundReport,")
text = remove_line_containing(text, "required this.postRoundToLedger,")
text = remove_line_containing(text, "required this.getRoundLeaderboard,")

# --- Section B: المعاملات الاختيارية Type? name ---
text = remove_line_containing(text, "ScoreRound? scoreRound,")
text = remove_line_containing(text, "ScoreRoundsForFixture? scoreRoundsForFixture,")
text = remove_line_containing(text, "GetRoundScores? getRoundScores,")
text = remove_line_containing(text, "GetRoundReport? getRoundReport,")
text = remove_line_containing(text, "AdminGetRoundScores? adminGetRoundScores,")
text = remove_line_containing(text, "AdminGetRoundReport? adminGetRoundReport,")
text = remove_line_containing(text, "PostRoundToLedger? postRoundToLedger,")
text = remove_line_containing(text, "GetRoundLeaderboard? getRoundLeaderboard,")

# --- Section E: تصريحات الحقول (بترتيب الملف — يضمن أن حذف adminGetRoundScores
# يسبق adminGetRoundReport فيستهلك التعليق المشترك بينهما بشكل صحيح) ---
text = remove_field(text, "final ScoreRound scoreRound;")
text = remove_field(text, "final ScoreRoundsForFixture scoreRoundsForFixture;")
text = remove_field(text, "final GetRoundScores getRoundScores;")
text = remove_field(text, "final GetRoundReport getRoundReport;")
text = remove_field(text, "final AdminGetRoundScores adminGetRoundScores;")
text = remove_field(text, "final AdminGetRoundReport adminGetRoundReport;")
text = remove_field(text, "final PostRoundToLedger postRoundToLedger;")
text = remove_field(text, "final GetRoundLeaderboard getRoundLeaderboard;")

# --- تعليق توثيقي يتيم: كان يصف postRoundToLedger لكنه أصبح منزلقًا فوق حقل
# adminGetParticipantDisplayNames غير ذي الصلة قبل هذا التعديل ---
text = remove_doc_block_before(
    text,
    "Posts a scored round to the append-only Ledger (admin-only command; the",
    "final AdminGetParticipantDisplayNames adminGetParticipantDisplayNames;",
)

# --- Section F: كتلة الربط الفعلية (bootstrap wiring) ---
text = remove_named_arg(text, "scoreRound: ScoreRound(")
text = remove_named_arg(text, "scoreRoundsForFixture: ScoreRoundsForFixture(")
text = remove_named_arg(text, "getRoundScores: GetRoundScores(")
text = remove_named_arg(text, "getRoundReport: GetRoundReport(")
text = remove_named_arg(text, "adminGetRoundScores: AdminGetRoundScores(")
text = remove_named_arg(text, "adminGetRoundReport: AdminGetRoundReport(")
text = remove_named_arg(text, "postRoundToLedger: PostRoundToLedger(")
text = remove_named_arg(text, "getRoundLeaderboard: GetRoundLeaderboard(")

# --- إصلاح 3 مراجع توثيقية متدلية داخل تعليقات مُبقاة ---
text = fix_bracket_ref(text, "[scoreRound],", "scoreRound,")
text = fix_bracket_ref(text, "[postRoundToLedger]", "postRoundToLedger")
text = fix_bracket_ref(text, "[_absentAdminGetRoundScores]", "_absentAdminGetRoundScores")

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
backup_dir = pathlib.Path.home() / "nukhbaa-round-backups" / ("composition_root_" + ts)
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
    "- [" + now + "] تنظيف: إزالة ربط ثمانية use-cases ميتة (ScoreRound، "
    "ScoreRoundsForFixture، GetRoundScores، GetRoundReport، AdminGetRoundScores، "
    "AdminGetRoundReport، PostRoundToLedger، GetRoundLeaderboard) من "
    "composition_root.dart — معاملات مُنشئ (required+اختيارية)، دوال _absentX، "
    "تصريحات الحقول، تعليق يتيم كان يصف postRoundToLedger، كتلة الربط الفعلية؛ "
    "مع إصلاح 3 مراجع توثيقية متدلية ([scoreRound]، [postRoundToLedger]، "
    "[_absentAdminGetRoundScores]) | ملف: "
    "apps/server/lib/composition/composition_root.dart | اختبار: " + test_status + "\n"
)
with open("docs/checkpoints/session-log.md", "a", encoding="utf-8") as f:
    f.write(log_line)

subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(
    [
        "git",
        "commit",
        "-m",
        "chore(server): unwire 8 dead Round use-cases from composition_root",
    ],
    check=True,
)

print("")
print("تم والكوميت محليًا. لا دفع (push) بلا إذن صريح.")
if not ok:
    sys.exit(1)
