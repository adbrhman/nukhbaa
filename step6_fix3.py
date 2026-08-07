#!/usr/bin/env python3
"""step6_fix3 — يصحّح لنت prefer_function_declarations_over_variables الوحيدة
المتبقية بملف prediction_screen_test.dart (موروثة من step6.py الأصلي)."""

import sys

PATH = "apps/mobile/test/features/prediction/prediction_screen_test.dart"

OLD = (
    "        final submitButton = () => tester.widget<FilledButton>(\n"
    "          find.byKey(const Key('prediction.submit')),\n"
    "        );\n"
)
NEW = (
    "        FilledButton submitButton() => tester.widget<FilledButton>(\n"
    "          find.byKey(const Key('prediction.submit')),\n"
    "        );\n"
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
