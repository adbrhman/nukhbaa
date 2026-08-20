#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="${1:-$(pwd)}"
cd "$REPO_DIR"
F="apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart"
[ -f "$F" ] || { echo "خطأ: لم أجد $F هنا."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 غير مثبت."; exit 1; }

python3 - "$F" << 'PYEOF'
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()

def do_replace(label, old, new, required=True):
    global s
    n = s.count(old)
    if n == 0:
        if required:
            print(f"  ! لم يُطابَق: {label} — تخطّي (قد يكون معدّلاً مسبقاً)")
        return
    if n > 1:
        print(f"  ! تحذير: {label} تطابق {n} مرات، سيُستبدل الجميع")
    s = s.replace(old, new)
    print(f"  OK  {label} ({n})")

do_replace(
    "حذف كتلة _hof/_names/_nameOf",
    """    final _hof = ref.watch(hallOfFameProvider);
    final Map<String, String> _names = <String, String>{
      for (final e in (_hof.asData?.value.entries ?? const []))
        e.userId: e.displayName,
    };
    String _nameOf(String id) => _names[id] ?? id;
""",
    "",
)

do_replace(
    "title: _nameOf(scores[i].participantId)",
    "title: _nameOf(scores[i].participantId),",
    "title: scores[i].displayName.isNotEmpty\n"
    "                          ? scores[i].displayName\n"
    "                          : scores[i].participantId,",
)

do_replace(
    "استدعاء _RoundReportRowCard بدون nameOf",
    "_RoundReportRowCard(row: row, nameOf: _nameOf),",
    "_RoundReportRowCard(row: row),",
)

do_replace(
    "حذف مُنشئ nameOf",
    "const _RoundReportRowCard({required this.row, required this.nameOf});",
    "const _RoundReportRowCard({required this.row});",
)
do_replace(
    "حذف حقل nameOf",
    "  final RoundReportRow row;\n  final String Function(String) nameOf;\n",
    "  final RoundReportRow row;\n",
)

do_replace(
    "nameOf(row.participantId)",
    "nameOf(row.participantId),",
    "row.displayName.isNotEmpty\n"
    "                      ? row.displayName\n"
    "                      : row.participantId,",
)

open(path, "w", encoding="utf-8").write(s)
print("تم الحفظ.")
PYEOF

echo
echo "=== تحقق نهائي (يجب ألا تظهر أي نتيجة) ==="
grep -n "_hof\|_nameOf\|nameOf(" "$F" || echo "نظيف — لا بقايا."
echo
echo "=== git diff -- $F ==="
git diff -- "$F" 2>/dev/null || true
