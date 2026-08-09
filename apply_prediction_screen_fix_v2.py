#!/usr/bin/env python3
"""
إصلاح: تعليق (hang) شاشة التوقعات عند فتح جولة سبق التوقع لها.

هذا الإصدار (v2) يصحّح أيضًا محاولة إصلاح سابقة استخدمت
`ref.listen(..., fireImmediately: true)` — وهو معامل غير معرّف على
WidgetRef.listen (متاح فقط على ProviderContainer.listen)، فسبّب:
  error • The named parameter 'fireImmediately' isn't defined.

السبب الجذري الأصلي: _PredictionEditorState.build() كان يعبئ
TextEditingController مباشرة من `.whenData(...)` أثناء build() نفسه.
بما أن myPredictionProvider قراءة غير متزامنة، تصل النتيجة في بناء
لاحق بعد أن تكون حقول TextField قد بُنيت فعلاً — فتؤدي كتابة
controller.text إلى إشعار مستمعي تلك الحقول (setState) أثناء قفل مرحلة
البناء، فيرمي Flutter:
  "setState() or markNeedsBuild() called during build"

الإصلاح الصحيح: تأجيل التعبئة عبر WidgetsBinding.instance.
addPostFrameCallback بدل ref.listen (لا يعتمد على أي معامل قد يختلف
بين إصدارات Riverpod) — فتُطلق بعد انتهاء قفل مرحلة البناء بأمان.

طريقة التشغيل:
  ضعه في أي مكان داخل مستودع نُخبة (جذره أو أي مجلد فرعي منه) ثم:
    python3 apply_prediction_screen_fix_v2.py
  السكربت يكتشف جذر المستودع تلقائياً، ويتعرّف تلقائياً هل الملف على
  حالته الأصلية أو على النسخة السابقة (ref.listen الخاطئة) ويصحّحها.
  idempotent: تشغيله أكثر من مرة آمن ولن يكرر التعديل.
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


# الحالة الصحيحة (الهدف النهائي).
FIXED_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));
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
    }"""

# الحالة الأصلية (قبل أي إصلاح) — .whenData مباشرة داخل build().
ORIGINAL_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));
    final mine = ref.watch(myPredictionProvider(widget.roundId));
    final inFlight = submission is SubmissionInFlight;

    // Pre-fill from the stored prediction (once) when it resolves non-null.
    mine.whenData((prediction) {
      if (prediction != null) {
        _applyPrefill(prediction);
      }
    });"""

# محاولة الإصلاح السابقة (ref.listen + fireImmediately) — كانت خاطئة.
BROKEN_ATTEMPT_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));

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
            print("✗ تعذّر اكتشاف جذر المستودع (لا يوجد melos.yaml/pubspec.yaml مناسب في الأعلى).")
            print("  مرّر المسار صراحة: python3 apply_prediction_screen_fix_v2.py /path/to/nukhba")
            return 1

    target = repo_root / REL_PATH
    if not target.exists():
        print(f"✗ الملف غير موجود: {target}")
        print(f"  (جذر المستودع المكتشف: {repo_root})")
        return 1

    text = target.read_text(encoding="utf-8")

    if FIXED_BLOCK in text:
        print(f"✓ الإصلاح الصحيح مطبّق مسبقاً في: {target}")
        return 0

    if BROKEN_ATTEMPT_BLOCK in text:
        text = text.replace(BROKEN_ATTEMPT_BLOCK, FIXED_BLOCK, 1)
        target.write_text(text, encoding="utf-8")
        print(f"✓ صُحّحت محاولة الإصلاح السابقة (ref.listen الخاطئة) في: {target}")
        print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . على المستودع.")
        return 0

    if ORIGINAL_BLOCK in text:
        text = text.replace(ORIGINAL_BLOCK, FIXED_BLOCK, 1)
        target.write_text(text, encoding="utf-8")
        print(f"✓ تم إصلاح: {target}")
        print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . على المستودع.")
        return 0

    print("✗ لم يتم العثور على أي من النصوص المتوقعة (الأصلية أو المُصلَحة سابقاً) —")
    print("  الملف قد يكون تغيّر يدوياً. لم يُعدَّل شيء (لتفادي تلف الملف).")
    print(f"  المسار: {target}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
"""
إصلاح: تعليق (hang) شاشة التوقعات عند فتح جولة سبق التوقع لها.

هذا الإصدار (v2) يصحّح أيضًا محاولة إصلاح سابقة استخدمت
`ref.listen(..., fireImmediately: true)` — وهو معامل غير معرّف على
WidgetRef.listen (متاح فقط على ProviderContainer.listen)، فسبّب:
  error • The named parameter 'fireImmediately' isn't defined.

السبب الجذري الأصلي: _PredictionEditorState.build() كان يعبئ
#!/usr/bin/env python3
"""
إصلاح: تعليق (hang) شاشة التوقعات عند فتح جولة سبق التوقع لها.

هذا الإصدار (v2) يصحّح أيضًا محاولة إصلاح سابقة استخدمت
`ref.listen(..., fireImmediately: true)` — وهو معامل غير معرّف على
WidgetRef.listen (متاح فقط على ProviderContainer.listen)، فسبّب:
  error • The named parameter 'fireImmediately' isn't defined.

السبب الجذري الأصلي: _PredictionEditorState.build() كان يعبئ
TextEditingController مباشرة من `.whenData(...)` أثناء build() نفسه.
بما أن myPredictionProvider قراءة غير متزامنة، تصل النتيجة في بناء
لاحق بعد أن تكون حقول TextField قد بُنيت فعلاً — فتؤدي كتابة
controller.text إلى إشعار مستمعي تلك الحقول (setState) أثناء قفل مرحلة
البناء، فيرمي Flutter:
  "setState() or markNeedsBuild() called during build"

الإصلاح الصحيح: تأجيل التعبئة عبر WidgetsBinding.instance.
addPostFrameCallback بدل ref.listen (لا يعتمد على أي معامل قد يختلف
بين إصدارات Riverpod) — فتُطلق بعد انتهاء قفل مرحلة البناء بأمان.

طريقة التشغيل:
  ضعه في أي مكان داخل مستودع نُخبة (جذره أو أي مجلد فرعي منه) ثم:
    python3 apply_prediction_screen_fix_v2.py
  السكربت يكتشف جذر المستودع تلقائياً، ويتعرّف تلقائياً هل الملف على
  حالته الأصلية أو على النسخة السابقة (ref.listen الخاطئة) ويصحّحها.
  idempotent: تشغيله أكثر من مرة آمن ولن يكرر التعديل.
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


# الحالة الصحيحة (الهدف النهائي).
FIXED_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));
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
    }"""

# الحالة الأصلية (قبل أي إصلاح) — .whenData مباشرة داخل build().
ORIGINAL_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));
    final mine = ref.watch(myPredictionProvider(widget.roundId));
    final inFlight = submission is SubmissionInFlight;

    // Pre-fill from the stored prediction (once) when it resolves non-null.
    mine.whenData((prediction) {
      if (prediction != null) {
        _applyPrefill(prediction);
      }
    });"""

# محاولة الإصلاح السابقة (ref.listen + fireImmediately) — كانت خاطئة.
BROKEN_ATTEMPT_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));

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
            print("✗ تعذّر اكتشاف جذر المستودع (لا يوجد melos.yaml/pubspec.yaml مناسب في الأعلى).")
            print("  مرّر المسار صراحة: python3 apply_prediction_screen_fix_v2.py /path/to/nukhba")
            return 1

    target = repo_root / REL_PATH
    if not target.exists():
        print(f"✗ الملف غير موجود: {target}")
        print(f"  (جذر المستودع المكتشف: {repo_root})")
        return 1

    text = target.read_text(encoding="utf-8")

    if FIXED_BLOCK in text:
        print(f"✓ الإصلاح الصحيح مطبّق مسبقاً في: {target}")
        return 0

    if BROKEN_ATTEMPT_BLOCK in text:
        text = text.replace(BROKEN_ATTEMPT_BLOCK, FIXED_BLOCK, 1)
        target.write_text(text, encoding="utf-8")
        print(f"✓ صُحّحت محاولة الإصلاح السابقة (ref.listen الخاطئة) في: {target}")
        print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . على المستودع.")
        return 0

    if ORIGINAL_BLOCK in text:
        text = text.replace(ORIGINAL_BLOCK, FIXED_BLOCK, 1)
        target.write_text(text, encoding="utf-8")
        print(f"✓ تم إصلاح: {target}")
        print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . على المستودع.")
        return 0

    print("✗ لم يتم العثور على أي من النصوص المتوقعة (الأصلية أو المُصلَحة سابقاً) —")
    print("  الملف قد يكون تغيّر يدوياً. لم يُعدَّل شيء (لتفادي تلف الملف).")
    print(f"  المسار: {target}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
TextEditingController مباشرة من `.whenData(...)` أثناء build() نفسه.
بما أن myPredictionProvider قراءة غير متزامنة، تصل النتيجة في بناء
لاحق بعد أن تكون حقول TextField قد بُنيت فعلاً — فتؤدي كتابة
controller.text إلى إشعار مستمعي تلك الحقول (setState) أثناء قفل مرحلة
البناء، فيرمي Flutter:
  "setState() or markNeedsBuild() called during build"

الإصلاح الصحيح: تأجيل التعبئة عبر WidgetsBinding.instance.
addPostFrameCallback بدل ref.listen (لا يعتمد على أي معامل قد يختلف
بين إصدارات Riverpod) — فتُطلق بعد انتهاء قفل مرحلة البناء بأمان.

طريقة التشغيل:
  ضعه في أي مكان داخل مستودع نُخبة (جذره أو أي مجلد فرعي منه) ثم:
    python3 apply_prediction_screen_fix_v2.py
  السكربت يكتشف جذر المستودع تلقائياً، ويتعرّف تلقائياً هل الملف على
  حالته الأصلية أو على النسخة السابقة (ref.listen الخاطئة) ويصحّحها.
  idempotent: تشغيله أكثر من مرة آمن ولن يكرر التعديل.
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


# الحالة الصحيحة (الهدف النهائي).
FIXED_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));
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
    }"""

# الحالة الأصلية (قبل أي إصلاح) — .whenData مباشرة داخل build().
ORIGINAL_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));
    final mine = ref.watch(myPredictionProvider(widget.roundId));
    final inFlight = submission is SubmissionInFlight;

    // Pre-fill from the stored prediction (once) when it resolves non-null.
    mine.whenData((prediction) {
      if (prediction != null) {
        _applyPrefill(prediction);
      }
    });"""

# محاولة الإصلاح السابقة (ref.listen + fireImmediately) — كانت خاطئة.
BROKEN_ATTEMPT_BLOCK = """    final submission = ref.watch(predictionControllerProvider(widget.roundId));

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
            print("✗ تعذّر اكتشاف جذر المستودع (لا يوجد melos.yaml/pubspec.yaml مناسب في الأعلى).")
            print("  مرّر المسار صراحة: python3 apply_prediction_screen_fix_v2.py /path/to/nukhba")
            return 1

    target = repo_root / REL_PATH
    if not target.exists():
        print(f"✗ الملف غير موجود: {target}")
        print(f"  (جذر المستودع المكتشف: {repo_root})")
        return 1

    text = target.read_text(encoding="utf-8")

    if FIXED_BLOCK in text:
        print(f"✓ الإصلاح الصحيح مطبّق مسبقاً في: {target}")
        return 0

    if BROKEN_ATTEMPT_BLOCK in text:
        text = text.replace(BROKEN_ATTEMPT_BLOCK, FIXED_BLOCK, 1)
        target.write_text(text, encoding="utf-8")
        print(f"✓ صُحّحت محاولة الإصلاح السابقة (ref.listen الخاطئة) في: {target}")
        print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . على المستودع.")
        return 0

    if ORIGINAL_BLOCK in text:
        text = text.replace(ORIGINAL_BLOCK, FIXED_BLOCK, 1)
        target.write_text(text, encoding="utf-8")
        print(f"✓ تم إصلاح: {target}")
        print("  التالي: dart format ثم dart analyze --fatal-infos --fatal-warnings . على المستودع.")
        return 0

    print("✗ لم يتم العثور على أي من النصوص المتوقعة (الأصلية أو المُصلَحة سابقاً) —")
    print("  الملف قد يكون تغيّر يدوياً. لم يُعدَّل شيء (لتفادي تلف الملف).")
    print(f"  المسار: {target}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
