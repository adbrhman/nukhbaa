#!/usr/bin/env python3
import pathlib
import sys

PATH = pathlib.Path("apps/mobile/test/features/admin/admin_dashboard_screen_test.dart")

IMPORT_OLD = "import '../../support/admin_harness.dart';\n"
IMPORT_NEW = (
    "import 'package:mobile/features/admin/admin_providers.dart';\n"
    "\n"
    "import '../../support/admin_harness.dart';\n"
)

PROBE_OLD = (
    "      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));\n"
    "      await tester.pumpAndSettle();\n"
    "\n"
    "      expect(find.byKey(const Key('browse.error')), findsOneWidget);\n"
    "      expect(find.byKey(const Key('browse.error.retry')), findsOneWidget);\n"
)
PROBE_NEW = (
    "      await tester.pumpWidget(_host(harness, const AdminDashboardScreen()));\n"
    "      await tester.pumpAndSettle();\n"
    "\n"
    "      // ignore: avoid_print\n"
    "      debugPrint(\n"
    "        'PROBE auditLogProvider = '\n"
    "        '${harness.container.read(auditLogProvider)}',\n"
    "      );\n"
    "\n"
    "      expect(find.byKey(const Key('browse.error')), findsOneWidget);\n"
    "      expect(find.byKey(const Key('browse.error.retry')), findsOneWidget);\n"
)


def main() -> None:
    if not PATH.exists():
        sys.exit(f"خطأ: الملف غير موجود: {PATH}")
    text = PATH.read_text(encoding="utf-8")
    if IMPORT_OLD not in text:
        sys.exit("خطأ: نص الاستيراد المطلوب استبداله غير موجود بالملف.")
    if text.count(IMPORT_OLD) != 1:
        sys.exit("خطأ: نص الاستيراد ظهر أكثر من مرة.")
    if PROBE_OLD not in text:
        sys.exit("خطأ: نص التست المستهدف غير موجود بالملف.")
    if text.count(PROBE_OLD) != 1:
        sys.exit("خطأ: نص التست ظهر أكثر من مرة.")
    text = text.replace(IMPORT_OLD, IMPORT_NEW, 1)
    text = text.replace(PROBE_OLD, PROBE_NEW, 1)
    PATH.write_text(text, encoding="utf-8")
    print(f"تم التعديل بنجاح: {PATH}")


if __name__ == "__main__":
    main()
