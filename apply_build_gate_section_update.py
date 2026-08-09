#!/usr/bin/env python3
"""
يُدرج التحديث الذي حدّده المستخدم حرفياً في docs/project-context.md:
  - §2: فقرة "حالة بوابة Build Verification Gate" (تُدرج قبل ## 3.)
  - §4: يُستبدل قسم "## 4. Next Task ..." بالكامل بنص §4 الجديد.

يعتمد على عناوين الأقسام الثابتة (## 2. Progress / ## 3. .../ ## 4. Next
Task / ## 5. Execution...) كنقاط ارتكاز، وليس على مطابقة كتلة نصية داخلية،
لذا لا يتأثر بأي صياغة سابقة داخل §4.

طريقة التشغيل:
  ضعه في أي مكان داخل مستودع نُخبة ثم:
    python3 apply_build_gate_section_update.py
  يكتشف جذر المستودع تلقائياً. idempotent.
"""

import sys
from pathlib import Path

CONTEXT_REL = Path("docs/project-context.md")

SECTION2_HEADER = "## 2. Progress"
SECTION3_HEADER = "## 3. Version-Verification Log"
SECTION4_HEADER = "## 4. Next Task"
SECTION5_HEADER = "## 5. Execution & Resume Rules"

MARKER_S2 = "### Build Verification Gate — حالة"
S2_BLOCK = f"""{MARKER_S2}

- §4 Build Verification Gate: مكتملة.
- جميع مراحل التنفيذ الـ12 السابقة لا تُعاد فتحها.
- تحقق Web مكتمل بنجاح.
- تحقق Android غير متاح في بيئة Codespaces الحالية لعدم وجود Android SDK.
- تحقق iOS متخطّى لأن البيئة ليست macOS ولا تحتوي Xcode.

"""

MARKER_S4 = "## 4. Build Verification Gate"
S4_BLOCK = f"""{MARKER_S4}

### النتيجة النهائية

| الخطوة | الحالة |
|---|---|
| 1-3 | ✅ مؤكدة سابقًا |
| 4 `dart analyze` | ✅ No issues found |
| 5 `flutter test` / `dart test` | ✅ All tests passed |
| 6 `flutter build web` | ✅ Built successfully |
| 7 `flutter build apk` | 🔴 BLOCKED — Android SDK غير موجود في Codespaces |
| 8 `flutter build ios` | ⬜ SKIPPED — يتطلب macOS/Xcode |

**الحكم:** بوابة §4 مكتملة. فشل Android ليس فشلًا في المشروع، وإنما قيد في
بيئة التحقق الحالية. لا تُعاد فتح المراحل الـ12 بسبب ذلك.

لا تضف أي تبعية أو تعدّل المعمارية بسبب هذا القيد.

"""


def find_repo_root(start: Path) -> Path | None:
    for candidate in [start, *start.parents]:
        if (candidate / "melos.yaml").exists():
            return candidate
        pubspec = candidate / "pubspec.yaml"
        if pubspec.exists() and (candidate / "apps" / "mobile").is_dir():
            try:
                content = pubspec.read_text(encoding="utf-8")
            except OSError:
                continue
            if any(
                line.rstrip() == "melos:" or line.startswith("melos:")
                for line in content.splitlines()
            ):
                return candidate
    return None


def main() -> int:
    if len(sys.argv) > 1:
        repo_root = Path(sys.argv[1]).expanduser().resolve()
    else:
        repo_root = find_repo_root(Path.cwd()) or find_repo_root(
            Path(__file__).resolve().parent
        )
        if repo_root is None:
            print("✗ تعذّر اكتشاف جذر المستودع. مرّر المسار صراحة كوسيط.")
            return 1

    target = repo_root / CONTEXT_REL
    if not target.exists():
        print(f"✗ الملف غير موجود: {target}")
        return 1

    text = target.read_text(encoding="utf-8")
    changed = False

    # §2 — إدراج قبل "## 3. Version-Verification Log"
    if MARKER_S2 not in text:
        idx = text.find(SECTION3_HEADER)
        if idx == -1:
            print(f"✗ لم يتم العثور على '{SECTION3_HEADER}' — تخطّي §2.")
        else:
            text = text[:idx] + S2_BLOCK + text[idx:]
            changed = True
            print("✓ فقرة §2 أُدرجت.")
    else:
        print("✓ فقرة §2 موجودة مسبقاً.")

    # §4 — استبدال كامل بين "## 4. Next Task" و"## 5. Execution & Resume Rules"
    if MARKER_S4 not in text:
        start = text.find(SECTION4_HEADER)
        end = text.find(SECTION5_HEADER)
        if start == -1 or end == -1 or end <= start:
            print("✗ لم يتم العثور على حدود القسم §4 — لم يُعدَّل.")
        else:
            text = text[:start] + S4_BLOCK + text[end:]
            changed = True
            print("✓ القسم §4 استُبدل بالنص الجديد.")
    else:
        print("✓ القسم §4 مُحدَّث مسبقاً.")

    if changed:
        target.write_text(text, encoding="utf-8")
        print(f"✓ حُفظ: {target}")
    else:
        print("لا تغييرات لازمة — الملف محدَّث مسبقاً بالكامل.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
