# ✅ محلول بالكامل (كان P0) — آخر تأكيد 2026-09-02

**الخطوات 1-4 من "الحل المطلوب" أدناه مؤتمتة بالكامل فعليًا** في
`.github/workflows/build-verification.yml` (خطوات "Decode release keystore"،
"Write key.properties"، حقن `signingConfigs.release` في
`android/app/build.gradle(.kts)`، وخطوة "Verify release signing (apksigner)"
~السطور 362-378 التي تحسب SHA-256 الفعلي لكل APK موقَّع وتقارنه بالسرّ
وتُفشل الـCI عند أي اختلاف). الأسرار الخمسة المطلوبة (`ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`,
`ANDROID_CERT_SHA256`) مؤكَّدة موجودة على الريبو (`gh secret list`، 2026-09-02).

---

# الحالة الأصلية (مؤرَّخة، للسياق التاريخي فقط)

# P0 BLOCKER — APK release signing غير ثابت (OTA لا يعمل عبر الإصدارات)

الحالة المؤكدة بعد فحص المستودع (2026-08-21):

- `apps/mobile/android/` غير موجود في git — يُولَّد بالكامل بـ
  `flutter create --platforms=android` داخل CI في كل build.
- لا يوجد `keystore` ولا `key.properties` ولا `signingConfigs`
  release في أي مكان في المستودع.
- نتيجة ذلك: `flutter build apk --release` يوقّع بـ **debug keystore**
  يُولَّد محليًا في بيئة CI، وقد يختلف بين عمليات البناء.

## لماذا يمنع هذا OTA
Android يرفض تثبيت تحديث APK إذا كان موقّعًا بمفتاح مختلف عن المثبَّت
حاليًا (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). بدون release key ثابت،
مستخدم مثبِّت لبناء سابق لن يستطيع تثبيت البناء الجديد عبر OTA — سيفشل
التثبيت دائمًا. لذلك **مسار OTA غير جاهز للإنتاج حتى يُحلّ هذا**.

## الحل المطلوب (يدويًا، خارج هذا السكربت — لا نضع أسرارًا في git)
1. أنشئ upload/release keystore مرة واحدة محليًا (لا يُرفع إلى git).
2. خزّن المفتاح وكلماته كـ GitHub Actions Secrets:
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
   `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
3. في CI بعد `flutter create`: فُكّ ترميز الـkeystore إلى ملف، أنشئ
   `android/key.properties`، واحقن `signingConfigs.release` في
   `android/app/build.gradle(.kts)` بحيث `buildTypes.release` يستخدمه.
4. تحقّق من التوقيع: `apksigner verify --print-certs <apk>` وثبّت أن
   بصمة SHA-256 للشهادة ثابتة بين الإصدارات.

## ملاحظة أمنية
SHA-256 في مسار OTA يضمن **integrity** فقط (الملف يطابق القيمة المنشورة).
**authenticity** (هوية الناشر) تأتي حصريًا من ثبات APK signing key أعلاه.
لا تعتبر SHA-256 بديلًا عن التوقيع.

## Google Play
مسار REQUEST_INSTALL_PACKAGES + native installer صالح للتوزيع الخارجي فقط.
عند الانتقال إلى Google Play يجب استبداله بـ Play In-App Updates API.
