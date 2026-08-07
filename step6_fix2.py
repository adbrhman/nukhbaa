#!/usr/bin/env python3
"""step6_fix2 — يصحّح خطأ اقتباس Dart بملف prediction_screen_test.dart
(موروث من step6.py الأصلي، مو من step6_fix.py) — سطر عنوان الاختبار الثاني
كان يخلط ' و " بشكل يكسر الـ string، سبب 28 خطأ تسلسلي بالـ analyzer.
"""

import sys

PATH = "apps/mobile/test/features/prediction/prediction_screen_test.dart"

OLD = (
    "    testWidgets(\n"
    "      'a round whose fixtures have all already kicked off shows the '\n"
    "      \"nothing left to predict\" message and no submit affordance is usable\",\n"
    "      (tester) async {\n"
)
NEW = (
    "    testWidgets(\n"
    "      'a round whose fixtures have all already kicked off shows the '\n"
    "      '\"nothing left to predict\" message and no submit affordance is usable',\n"
    "      (tester) async {\n"
)


def main() -> int:
    try:
        with open(PATH, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"XX: الملف غير موجود: {PATH}", file=sys.stderr)
        return 1

    count = content.count(OLD)
    if count != 1:
        print(
            f"XX: {PATH}: تطابق={count} (متوقع 1) لهذا المقطع:\n{OLD[:120]!r}...",
            file=sys.stderr,
        )
        return 1

    content = content.replace(OLD, NEW)
    with open(PATH, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"OK: {PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
