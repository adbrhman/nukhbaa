#!/usr/bin/env python3
"""يصحح اختبارين هشّين بـ admin_dashboard_screen_test.dart:
1) اختبار transient failure كان يستخدم errorEnvelope(503) بدل throw Exception
   (النمط المُثبَت بباقي اختبارات المشروع لمحاكاة عطل نقل عابر).
2) اختبار نجاح suspend كان يفترض auditCalls>=2 رغم أن auditLogProvider
   بدون keepAlive (autoDispose) وينحذف عند مغادرة تبويب Audit — الافتراض
   خاطئ بالاختبار نفسه، لا علاقة له بمنطق الشاشة."""

import sys

PATH = "apps/mobile/test/features/admin/admin_dashboard_screen_test.dart"

OLD_1 = """      var callCount = 0;
      final harness = buildAdminHarness((request) async {
        callCount++;
        if (callCount == 1) {
          return errorEnvelope(503, 'server.unavailable', 'try again');
        }
        return okJsonObject(twoAuditEntries.toJson());
      });"""
NEW_1 = """      var callCount = 0;
      final harness = buildAdminHarness((request) async {
        callCount++;
        if (callCount == 1) throw Exception('offline');
        return okJsonObject(twoAuditEntries.toJson());
      });"""

OLD_2 = """      var auditCalls = 0;
      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          auditCalls++;
          return okJsonObject(emptyAuditLog.toJson());
        }
        if (request.method == 'POST' &&
            request.url.path == '/admin/users/user-9/suspend') {
          return okJsonObject(suspendedResult.toJson());
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });"""
NEW_2 = """      final harness = buildAdminHarness((request) async {
        if (request.method == 'GET' && request.url.path == '/admin/audit') {
          return okJsonObject(emptyAuditLog.toJson());
        }
        if (request.method == 'POST' &&
            request.url.path == '/admin/users/user-9/suspend') {
          return okJsonObject(suspendedResult.toJson());
        }
        return errorEnvelope(404, 'not_found', 'unexpected request');
      });"""

OLD_3 = """      expect(find.byKey(const Key('admin.users.result')), findsOneWidget);
      expect(find.byKey(const Key('admin.users.error')), findsNothing);
      // The initial load (tab build) plus the post-suspend invalidation.
      expect(auditCalls, greaterThanOrEqualTo(2));
    });"""
NEW_3 = """      expect(find.byKey(const Key('admin.users.result')), findsOneWidget);
      expect(find.byKey(const Key('admin.users.error')), findsNothing);
    });"""


def apply(content: str, old: str, new: str, label: str) -> str:
    count = content.count(old)
    if count != 1:
        print(f"XX: تطابق={count} (متوقع 1) لـ {label}", file=sys.stderr)
        sys.exit(1)
    return content.replace(old, new)


def main() -> int:
    try:
        with open(PATH, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"XX: الملف غير موجود: {PATH}", file=sys.stderr)
        return 1

    content = apply(content, OLD_1, NEW_1, "OLD_1 (transient failure)")
    content = apply(content, OLD_2, NEW_2, "OLD_2 (auditCalls handler)")
    content = apply(content, OLD_3, NEW_3, "OLD_3 (auditCalls assertion)")

    with open(PATH, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"OK: {PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

