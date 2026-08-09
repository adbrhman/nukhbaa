#!/usr/bin/env python3
"""
إصلاح: تعليق (hang) شاشة التوقعات عند فتح جولة سبق التوقع لها. (v3)

لماذا v3: السكربتان السابقان (v1/v2) يعتمدان على مطابقة كتلة نصية
حرفية كاملة. بعد تشغيل `dart format` على الملف، قد تتغيّر تفاصيل
تدوير الأسطر/المسافات داخل تلك الكتلة فلا تطابق النص المتوقع بعد
الآن، فيفشل السكربت بصمت (لا يُعدَّل شيء) رغم أن الخلل ما زال قائماً.
هذا الإصدار يعتمد بدل ذلك على نقطتي ارتكاز فريدتين (سطر البداية
الثابت وسطر النهاية الثابت) ويستبدل كل ما بينهما دفعة واحدة —
محصّن ضد إعادة تهيئة `dart format` الداخلية.

السبب الجذري: _PredictionEditorState.build() كان يعبئ
TextEditingController مباشرة من `.whenData(...)` أثناء build() نفسه.
بما أن myPredictionProvider قراءة غير متزامنة، تصل النتيجة في بناء
لاحق بعد أن تكون حقول TextField قد بُنيت فعلاً — فتؤدي كتابة
controller.text إلى إشعار مستمعي تلك الحقول (setState) أثناء قفل مرحلة
البناء، فيرمي Flutter:
  "setState() or markNeedsBuild() called during build"

محاولة سابقة استخدمت `ref.listen(..., fireImmediately: true)` وهو
معامل غير معرّف على WidgetRef.listen (متاح فقط على
ProviderContainer.listen) — سبّب خطأ ترجمة (undefined_named_parameter).

الإصلاح الصحيح والنهائي: تأجيل التعبئة عبر
WidgetsBinding.instance.addPostFrameCallback — لا يعتمد على أي معامل
قد يختلف بين إصدارات Riverpod، ويُنفَّذ بعد انتهاء قفل مرحلة البناء.

طريقة التشغيل:
  ضعه في أي مكان داخل مستودع نُخبة (جذره أو أي مجلد فرعي منه) ثم:
    python3 apply_prediction_screen_fix_v3.py
  السكربت يكتشف جذر المستودع تلقائياً. idempotent: تشغيله أكثر من
  مرة آمن ولن يكرر التعديل.
"""

import sys
from pathlib import Path

REL_PATH = Path("apps/mobile/lib/features/prediction/prediction_screen.dart")

START_MARKER = (
    "final submission = ref.watch(predictionControllerProvider(widget.roundId));"
)
END_MARKER = "final openFixtures = widget.fixtures.where((f) => !_isLocked(f)).toList();"

REPLACEMENT_BODY = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));
    final mine = ref.watch(myPredictionProvider(widget.roundId));
    final inFlight = submission is SubmissionInFlight;

    // Pre-fill from the stored prediction (once) when it resolves non-null.
    // Scheduled via `addPostFrameCallback` rather than mutating the
    // controllers inline here: by the time `myPrediction` resolves (an
    // async fetch), this row's `TextField`s are already mounted from a
    // prior frame, so writing `.text` directly during build would notify
    // their listeners — and call `setState`/`markNeedsBuild` on
    // already-built elements — while the framework's build phase is still
    // locked, throwing "setState() or markNeedsBuild() called during
    // build" and hanging the screen every time an already-predicted round
    // is opened. Deferring to the post-frame callback runs it once the
    // build phase is unlocked, so the same mutation is safe there.
    final storedPrediction = mine.value;
    if (storedPrediction != null && !_prefilled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _applyPrefill(storedPrediction));
      });
    }

    """


def find_repo_root(start: Path) -> Path | None:
    """يصعد من `start` بحثاً عن جذر مستودع نُخبة: إما melos.yaml مستقل،
    أو pubspec.yaml يحوي مفتاح `melos:` (تهيئة Melos المضمّنة في هذا
    المشروع)، مع التحقق من وجود apps/mobile كتأكيد إضافي."""
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
        repo_root = find_repo_root(Path.cwd())
        if repo_root is None:
            repo_root = find_repo_root(Path(__file__).resolve().parent)
        if repo_root is None:
            print("✗ تعذّر اكتشاف جذر المستودع (لا يوجد melos.yaml/pubspec.yaml مناسب في الأعلى).")
            print("  مرّر المسار صراحة: python3 apply_prediction_screen_fix_v3.py /path/to/nukhba")
            return 1

    target = repo_root / REL_PATH
    if not target.exists():
        print(f"✗ الملف غير موجود: {target}")
        print(f"  (جذر المستودع المكتشف: {repo_root})")
        return 1

    text = target.read_text(encoding="utf-8")

    if "addPostFrameCallback" in text and "fireImmediately" not in text:
        print(f"✓ الإصلاح الصحيح مطبّق مسبقاً في: {target}")
        return 0

    start_idx = text.find(START_MARKER)
    if start_idx == -1:
        print("✗ لم يتم العثور على نقطة الارتكاز الأولى (سطر ref.watch(predictionControllerProvider...)).")
        print("  الملف قد يكون تغيّر يدوياً بشكل غير متوقع. لم يُعدَّل شيء.")
        print(f"  المسار: {target}")
        return 1

    end_idx = text.find(END_MARKER, start_idx + len(START_MARKER))
    if end_idx == -1:
        print("✗ لم يتم العثور على نقطة الارتكاز الثانية (سطر final openFixtures ...).")
        print("  لم يُعدَّل شيء.")
        print(f"  المسار: {target}")
        return 1

    new_text = text[:start_idx] + REPLACEMENT_BODY + text[end_idx:]

    if new_text == text:
        print(f"✓ الإصلاح الصحيح مطبّق مسبقاً (لا تغيير لازم) في: {target}")
        return 0

    target.write_text(new_text, encoding="utf-8")
    print(f"✓ تم الإصلاح (v3، محصّن ضد إعادة تهيئة dart format): {target}")
    print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . على المستودع.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
