# نُخبة — Nukhba

منصّة توقعات لكرة القدم. Dart/Flutter monorepo على pub workspaces + Melos 8، بمعمارية Clean Architecture.

## البنية

- `packages/shared` — الأنواع المشتركة (`Result`, `AppError`).
- `packages/domain` — الكيانات وقواعد العمل. لا يعتمد على شيء خارجي.
- `packages/contracts` — عقود DTO المشتركة بين الخادم والعميل.
- `packages/application` — حالات الاستخدام.
- `packages/infrastructure` — Postgres/Supabase وتحقّق JWT.
- `packages/api_client` — عميل HTTP المُوَلَّد للعقود. الجهة الوحيدة التي تُصدر طلبات.
- `apps/server` — Dart Frog، الـ composition root ومسارات HTTP.
- `apps/mobile` — عميل Flutter (PWA + Android + iOS) بـ Riverpod codegen.
- `tooling/import_lint` — يفرض حدود الاعتماد بين الطبقات.
- `supabase/migrations` — مخطط قاعدة البيانات.

## المتطلبات

Flutter مثبّت على النسخة الواردة في `.fvmrc` (3.44.0). استخدم `fvm use`.

## البوابة المحلية (نفس CI)

    flutter pub get
    (cd apps/mobile && dart run build_runner build --delete-conflicting-outputs)
    dart run melos run verify

`melos run verify` هو الأمر الصحيح ويطابق تمامًا خطوات
`.github/workflows/build-verification.yml` (format-check ثم analyze ثم
import-lint ثم test ثم test-mobile). لا تستخدم `dart pub global run melos
run test` — هذا الأمر ناقص ويفترض تثبيتًا عامًا لـ melos غير لازم أصلًا،
لأن `melos` مُعرَّف كـ `dev_dependency` في `pubspec.yaml` الجذر ويُشغَّل عبر
`dart run melos ...`.

## الإعداد

انسخ `.env.example` إلى `.env` واملأ قيم Supabase. لا تُودِع `.env` في git إطلاقًا.

العميل يحتاج عنوان الـ API عند البناء:

    flutter run --dart-define=NUKHBA_API_BASE_URL=http://localhost:8080

في CI، عرّف متغيّر المستودع `NUKHBA_API_BASE_URL` من
Settings > Secrets and variables > Actions > Variables.

## حالة المشروع

- `docs/next-task.md` — المهمة التالية والحالة الحالية.
- `docs/project-context.md` — السياق المعماري الكامل.
- حالة البناء الفعلية هي دائمًا آخر run في تبويب Actions، لا أي ملف توثيق.

الواجهة المنشورة: https://adbrhman.github.io/nukhbaa/
