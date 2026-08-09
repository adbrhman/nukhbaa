#!/usr/bin/env python3
"""
إصلاح: تعليق (hang) شاشة التوقعات عند فتح جولة سبق التوقع لها.

السبب الجذري:
  _PredictionEditorState.build() في:
    apps/mobile/lib/features/prediction/prediction_screen.dart
  كان يستدعي mine.whenData(...) مباشرة داخل build() ليعبّئ
  TextEditingController بالقيم المخزّنة. بما أن myPredictionProvider
  قراءة غير متزامنة (Future)، فإن التعبئة تحدث في بناء لاحق بعد أن تكون
  حقول TextField قد بُنيت فعلاً من الإطار السابق — فتؤدي الكتابة في
  controller.text إلى إشعار مستمعي تلك الحقول (setState) بينما مرحلة
  البناء لا تزال مقفلة، فيرمي Flutter الاستثناء:
    "setState() or markNeedsBuild() called during build"
  وهذا يظهر للمستخدم كتعليق/تجمّد الشاشة — يحدث في كل مرة تُفتح فيها
  جولة سبق للمستخدم التوقع فيها (مسار أساسي شائع جداً).

الإصلاح:
  نقل التعبئة إلى ref.listen(...) بدل .whenData(...) المباشر داخل
  build — ref.listen في Riverpod يُطلق دالته خارج قفل مرحلة البناء،
  فتصبح كتابة controller.text آمنة.

طريقة التشغيل:
  ضعه في أي مكان داخل مستودع نُخبة (جذره أو أي مجلد فرعي منه) ثم:
    python3 apply_prediction_screen_fix.py
  السكربت يكتشف جذر المستودع تلقائياً (يبحث عن melos.yaml صعوداً من
  المجلد الحالي)، ولا يحتاج تعديل مسار يدوياً. إن فشل الاكتشاف، مرّر
  المسار صراحة:
    python3 apply_prediction_screen_fix.py /path/to/nukhba
  السكربت idempotent: تشغيله أكثر من مرة لن يكرر التعديل.
"""

import sys
from pathlib import Path

REL_PATH = Path("apps/mobile/lib/features/prediction/prediction_screen.dart")


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

OLD_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));
    final mine = ref.watch(myPredictionProvider(widget.roundId));
    final inFlight = submission is SubmissionInFlight;

    // Pre-fill from the stored prediction (once) when it resolves non-null.
    mine.whenData((prediction) {
      if (prediction != null) {
        _applyPrefill(prediction);
      }
    });"""

NEW_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));

    // Pre-fill from the stored prediction (once) when it resolves non-null.
    // Deferred via `ref.listen` rather than mutating the controllers inline
    // from a `.whenData` call in build: by the time `myPrediction` resolves
    // (an async fetch), this row's `TextField`s are already mounted from a
    // prior frame, so writing `.text` directly here would notify their
    // listeners — and call `setState`/`markNeedsBuild` on already-built
    // elements — while the framework's build phase is still locked,
    // throwing "setState() or markNeedsBuild() called during build" and
    // hanging the screen every time an already-predicted round is opened.
    // `ref.listen` fires this callback outside the locked build phase, so
    // the same mutation is safe there.
    ref.listen<AsyncValue<PredictionDto?>>(
      myPredictionProvider(widget.roundId),
      (previous, next) {
        final prediction = next.value;
        if (prediction != null) {
          setState(() => _applyPrefill(prediction));
        }
      },
      fireImmediately: true,
    );
    final mine = ref.watch(myPredictionProvider(widget.roundId));
    final inFlight = submission is SubmissionInFlight;"""


def main() -> int:
    if len(sys.argv) > 1:
        repo_root = Path(sys.argv[1]).expanduser().resolve()
    else:
        repo_root = find_repo_root(Path.cwd())
        if repo_root is None:
            repo_root = find_repo_root(Path(__file__).resolve().parent)
        if repo_root is None:
            print("✗ تعذّر اكتشاف جذر المستودع (لا يوجد melos.yaml في الأعلى).")
            print("  مرّر المسار صراحة: python3 apply_prediction_screen_fix.py /path/to/nukhba")
            return 1

    target = repo_root / REL_PATH
    if not target.exists():
        print(f"✗ الملف غير موجود: {target}")
        print(f"  (جذر المستودع المكتشف: {repo_root})")
        return 1

    text = target.read_text(encoding="utf-8")

    if NEW_BLOCK in text:
        print(f"✓ الإصلاح مطبّق مسبقاً في: {target}")
        return 0

    if OLD_BLOCK not in text:
        print("✗ لم يتم العثور على النص المستهدف بالضبط — الملف قد يكون")
        print("  تغيّر عن النسخة المتوقعة. لم يُعدَّل شيء (لتفادي تلف الملف).")
        print(f"  المسار: {target}")
        return 1

    text = text.replace(OLD_BLOCK, NEW_BLOCK, 1)
    target.write_text(text, encoding="utf-8")
    print(f"✓ تم إصلاح: {target}")
    print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . على المستودع.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
