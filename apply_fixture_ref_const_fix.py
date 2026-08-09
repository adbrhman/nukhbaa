#!/usr/bin/env python3
"""
إصلاح آخر بند متبقٍ في dart analyze: prefer_const_constructors
  packages/application/test/competition/browse_round_fixtures_test.dart:71:28

FixtureRef له مُنشئ const (const FixtureRef(super.value);) في
packages/domain/lib/src/competition/fixture_ref.dart، والاستدعاء هنا لم
يستخدم const رغم أن كل الوسائط ثوابت — إضافة الكلمة فقط.

طريقة التشغيل:
  ضعه في أي مكان داخل مستودع نُخبة (جذره أو أي مجلد فرعي منه) ثم:
    python3 apply_fixture_ref_const_fix.py
  يكتشف جذر المستودع تلقائياً. idempotent.
"""

import sys
from pathlib import Path

REL_PATH = Path(
    "packages/application/test/competition/browse_round_fixtures_test.dart"
)

OLD = "fixture: FixtureRef(_fa),"
NEW = "fixture: const FixtureRef(_fa),"


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

    target = repo_root / REL_PATH
    if not target.exists():
        print(f"✗ الملف غير موجود: {target}")
        return 1

    text = target.read_text(encoding="utf-8")

    if NEW in text:
        print(f"✓ الإصلاح مطبّق مسبقاً في: {target}")
        return 0

    if OLD not in text:
        print("✗ لم يتم العثور على السطر المتوقع — الملف قد يكون تغيّر.")
        print(f"  المسار: {target}")
        return 1

    text = text.replace(OLD, NEW, 1)
    target.write_text(text, encoding="utf-8")
    print(f"✓ تم الإصلاح: {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
