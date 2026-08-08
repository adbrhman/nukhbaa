#!/usr/bin/env python3
import pathlib
import re
import sys

PROVIDER_PATH = pathlib.Path("apps/mobile/lib/features/admin/admin_providers.dart")
TEST_PATH = pathlib.Path("apps/mobile/test/features/admin/admin_dashboard_screen_test.dart")


def main():
    if not PROVIDER_PATH.exists():
        sys.exit(f"خطأ: الملف غير موجود: {PROVIDER_PATH}")
    if not TEST_PATH.exists():
        sys.exit(f"خطأ: الملف غير موجود: {TEST_PATH}")

    provider_text = PROVIDER_PATH.read_text(encoding="utf-8")

    if "@Riverpod(keepAlive: true)" not in provider_text:
        sys.exit("خطأ: [provider] '@Riverpod(keepAlive: true)' غير موجود.")
    if provider_text.count("@Riverpod(keepAlive: true)") != 1:
        sys.exit("خطأ: [provider] ظهر أكثر من مرة.")

    start_marker = "/// `keepAlive: true`"
    end_marker = "ever sees the error state.\n"

    start_idx = provider_text.find(start_marker)
    if start_idx == -1:
        sys.exit("خطأ: [provider] مؤشر البداية غير موجود.")

    end_idx = provider_text.find(end_marker, start_idx)
    if end_idx == -1:
        sys.exit("خطأ: [provider] مؤشر النهاية غير موجود.")
    end_idx += len(end_marker)

    before = provider_text[:start_idx]
    if before.endswith("///\n"):
        before = before[: -len("///\n")]

    provider_text = before + provider_text[end_idx:]
    provider_text = provider_text.replace("@Riverpod(keepAlive: true)", "@riverpod", 1)

    if "@riverpod\nFuture<AuditLogDto> auditLog(Ref ref) async {" not in provider_text:
        sys.exit("خطأ: [provider] النتيجة غير متوقعة بعد الحذف.")

    PROVIDER_PATH.write_text(provider_text, encoding="utf-8")
    print(f"تم تعديل: {PROVIDER_PATH}")

    test_text = TEST_PATH.read_text(encoding="utf-8")

    host_pattern = re.compile(
        r"Widget _host\(AdminHarness harness, Widget child\) => ProviderScope\(\s*\n"
        r"\s*overrides:\s*harness\.overrides,\s*\n"
    )
    matches = host_pattern.findall(test_text)
    if not matches:
        sys.exit("خطأ: [_host] النمط غير موجود.")
    if len(matches) != 1:
        sys.exit("خطأ: [_host] النمط ظهر أكثر من مرة.")

    test_text = host_pattern.sub(
        "Widget _host(AdminHarness harness, Widget child) => UncontrolledProviderScope(\n"
        "  container: harness.container,\n",
        test_text,
        count=1,
    )

    lines = test_text.splitlines(keepends=True)
    kept = []
    removed = 0
    for line in lines:
        if "PROBE" in line or line.strip() == "// ignore: avoid_print":
            removed += 1
            continue
        kept.append(line)
    test_text = "".join(kept)

    if removed == 0:
        sys.exit("خطأ: [probes] لم يُحذف أي سطر.")

    TEST_PATH.write_text(test_text, encoding="utf-8")
    print(f"تم تعديل: {TEST_PATH} (حُذف {removed} سطر probe)")


if __name__ == "__main__":
    main()
