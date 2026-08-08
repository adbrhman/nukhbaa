#!/usr/bin/env python3
import pathlib
import sys

PROVIDER_PATH = pathlib.Path("apps/mobile/lib/features/admin/admin_providers.dart")
TEST_PATH = pathlib.Path("apps/mobile/test/features/admin/admin_dashboard_screen_test.dart")


def main() -> None:
    if not PROVIDER_PATH.exists():
        sys.exit(f"خطأ: الملف غير موجود: {PROVIDER_PATH}")
    if not TEST_PATH.exists():
        sys.exit(f"خطأ: الملف غير موجود: {TEST_PATH}")

    provider_old = (
        "/// `GET /admin/audit` — the append-only audit trail, newest first.\n"
        "@riverpod\n"
        "Future<AuditLogDto> auditLog(Ref ref) async {\n"
    )
    provider_new = (
        "/// `GET /admin/audit` — the append-only audit trail, newest first.\n"
        "///\n"
        "/// `keepAlive: true` — without it this `autoDispose` provider can be torn\n"
        "/// down and rebuilt mid-frame while it lives inside a `TabBarView`\n"
        "/// (`AdminDashboardScreen`'s audit tab), firing a second, fresh network\n"
        "/// call that silently overwrites a first-call failure before the user\n"
        "/// ever sees the error state.\n"
        "@Riverpod(keepAlive: true)\n"
        "Future<AuditLogDto> auditLog(Ref ref) async {\n"
    )
    text = PROVIDER_PATH.read_text(encoding="utf-8")
    if provider_old not in text:
        sys.exit("خطأ: [keepAlive] النص غير موجود بملف provider — توقفت بدون تعديل.")
    if text.count(provider_old) != 1:
        sys.exit("خطأ: [keepAlive] النص ظهر أكثر من مرة.")
    PROVIDER_PATH.write_text(text.replace(provider_old, provider_new, 1), encoding="utf-8")

    test_text = TEST_PATH.read_text(encoding="utf-8")

    import_old = (
        "import 'package:mobile/features/admin/admin_providers.dart';\n"
        "\n"
        "import '../../support/admin_harness.dart';\n"
    )
    import_new = "import '../../support/admin_harness.dart';\n"
    if import_old not in test_text:
        sys.exit("خطأ: [إزالة استيراد probe] غير موجود.")
    if test_text.count(import_old) != 1:
        sys.exit("خطأ: [إزالة استيراد probe] ظهر أكثر من مرة.")
    test_text = test_text.replace(import_old, import_new, 1)

    handler_old = (
        "        callCount++;\n"
        "        // ignore: avoid_print\n"
        "        debugPrint('PROBE handler call #$callCount ${request.method} ${request.url.path}');\n"
        "        if (callCount == 1) throw Exception('offline');\n"
    )
    handler_new = (
        "        callCount++;\n"
        "        if (callCount == 1) throw Exception('offline');\n"
    )
    if handler_old not in test_text:
        sys.exit("خطأ: [إزالة probe الـ handler] غير موجود.")
    if test_text.count(handler_old) != 1:
        sys.exit("خطأ: [إزالة probe الـ handler] ظهر أكثر من مرة.")
    test_text = test_text.replace(handler_old, handler_new, 1)

    widget_probe_old = (
        "      // ignore: avoid_print\n"
        "      debugPrint(\n"
        "        'PROBE loading=${find.byKey(const Key(\"browse.loading\")).evaluate().length} '\n"
        "        'error=${find.byKey(const Key(\"browse.error\")).evaluate().length} '\n"
        "        'empty=${find.byKey(const Key(\"browse.empty\")).evaluate().length} '\n"
        "        'list=${find.byKey(const Key(\"browse.list\")).evaluate().length}',\n"
        "      );\n"
        "\n"
    )
    if widget_probe_old not in test_text:
        sys.exit("خطأ: [إزالة probe الودجت] غير موجود.")
    if test_text.count(widget_probe_old) != 1:
        sys.exit("خطأ: [إزالة probe الودجت] ظهر أكثر من مرة.")
    test_text = test_text.replace(widget_probe_old, "", 1)

    TEST_PATH.write_text(test_text, encoding="utf-8")

    print(f"تم تعديل: {PROVIDER_PATH}")
    print(f"تم تعديل: {TEST_PATH}")


if __name__ == "__main__":
    main()
