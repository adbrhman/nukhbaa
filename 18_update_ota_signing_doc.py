#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
from pathlib import Path

REPO_ROOT = Path.cwd()
DOC = REPO_ROOT / "docs/ota-signing-blocker.md"


def fail(msg: str) -> None:
    print(f"✗ {msg}", file=sys.stderr)
    sys.exit(1)


def must_replace(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0:
        fail(f"لم يُعثر على النمط المتوقع ({label}) — توقفت بلا أي تعديل.")
    if count > 1:
        fail(f"النمط ({label}) تكرر {count} مرة — توقفت بلا أي تعديل.")
    return text.replace(old, new, 1)


def main() -> None:
    if not DOC.exists():
        fail("docs/ota-signing-blocker.md غير موجود — تأكد من التشغيل من جذر المستودع.")

    src = DOC.read_text(encoding="utf-8")

    if "# ✅ محلول بالكامل (كان P0)" in src:
        print("↷ الملف محدَّث مسبقًا — لا شيء لفعله. توقّف.")
        return

    src = must_replace(
        src,
        "# ✅ محلول جزئيًا (كان P0) — آخر تأكيد 2026-08-30",
        "# ✅ محلول بالكامل (كان P0) — آخر تأكيد 2026-09-02",
        "العنوان",
    )

    old_block = (
        "**الخطوات 1-3 من \"الحل المطلوب\" أدناه مؤتمتة بالكامل فعليًا** في\n"
        "`.github/workflows/build-verification.yml` (خطوات \"Decode release keystore\"،\n"
        "\"Write key.properties\"، وحقن `signingConfigs.release` في\n"
        "`android/app/build.gradle(.kts)` عبر سكربت Python مضمَّن). الأسرار الأربعة\n"
        "المطلوبة (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,\n"
        "`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`) مؤكَّدة موجودة على الريبو\n"
        "(`gh secret list`، 2026-08-30)."
    )
    new_block = (
        "**الخطوات 1-4 من \"الحل المطلوب\" أدناه مؤتمتة بالكامل فعليًا** في\n"
        "`.github/workflows/build-verification.yml` (خطوات \"Decode release keystore\"،\n"
        "\"Write key.properties\"، حقن `signingConfigs.release` في\n"
        "`android/app/build.gradle(.kts)`، وخطوة \"Verify release signing (apksigner)\"\n"
        "~السطور 362-378 التي تحسب SHA-256 الفعلي لكل APK موقَّع وتقارنه بالسرّ\n"
        "وتُفشل الـCI عند أي اختلاف). الأسرار الخمسة المطلوبة (`ANDROID_KEYSTORE_BASE64`,\n"
        "`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`,\n"
        "`ANDROID_CERT_SHA256`) مؤكَّدة موجودة على الريبو (`gh secret list`، 2026-09-02)."
    )
    src = must_replace(src, old_block, new_block, "فقرة الخطوات 1-3/1-4")

    old_missing = (
        "**لم يُنجَز بعد**: الخطوة 4 (التحقق الآلي بـ`apksigner verify --print-certs`\n"
        "من أن بصمة SHA-256 للشهادة ثابتة بين الإصدارات) — **غير موجودة في CI حاليًا**.\n"
        "هذا يعني أن التوقيع يُطبَّق بثبات نظريًا (نفس keystore/alias في كل تشغيل)، لكن\n"
        "لا يوجد تحقق آلي يفشل الـbuild لو تغيّرت البصمة بالخطأ (مثلًا سرّ اتُبدل خطأً).\n"
        "موصى به كخطوة CI إضافية مستقبلية، وليس عاجلًا طالما الأسرار لم تتغير.\n\n"
    )
    src = must_replace(src, old_missing, "", "فقرة لم يُنجز بعد")

    DOC.write_text(src, encoding="utf-8")
    print("✓ كُتب التعديل في docs/ota-signing-blocker.md")


if __name__ == "__main__":
    main()
