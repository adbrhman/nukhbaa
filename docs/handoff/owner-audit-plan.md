# خطة تنفيذ مستمرة: سجل تدقيق المالك المعزول (339 إلى 348)

نخبة (nukhbaa). أُعدّت 2026-11-26 من ملف «خطة إصلاح سجل تدقيق المالك» (Nukhbaa_Owner_Audit_Plan_321.docx) ومقارنتها بـ zip المستودع، وسجل الجلسات فيه ينتهي عند 338. الخطة الأصلية كانت سكربتاً واحداً برقم 321، وهنا قُسّمت إلى سكربتات مرقّمة صغيرة، كل واحد إصلاح واحد. الشجرة الفعلية تغلب هذه الخطة عند أي اختلاف. تحليل Dart واختباره يجريان على جهاز المالك وحده.

## 1. كيف تبدأ جلسة جديدة (حساب آخر)

1. من الطرفية على الجهاز، داخل المستودع:

   ```bash
   cd ~/nukhbaa-backup-1787537565 && git archive --format=zip -o /sdcard/Download/nukhbaa-latest.zip HEAD
   ```

   (يحمل آخر التزام محلي حتى غير المدفوع).
2. ارفع في الجلسة الجديدة ملفين: هذا الملف، و`nukhbaa-latest.zip`.
3. الصق هذه الرسالة كما هي:

   > اقرأ docs/agent-script-protocol.md و docs/project-context.md من الـzip، ثم خطة التنفيذ المرفقة (owner-audit-plan.md). نفّذ سكربتاً واحداً فقط، أول سكربت غير معلَّم في جدول المتابعة (القسم 5). تحقق من وجود كل ملف ودالة قبل الكتابة، فالشجرة الفعلية تغلب الخطة. لا تدفع. أخبرني بما لم يُختبر. الرد بالعربية وباختصار.

4. بعد كل سكربت ينجح، يعلّم المساعد صفه في الجدول، ويطلب zip جديداً قبل التالي إن مرّت جلسة بينهما.

## 2. قرارات المالك وقيود الخطة

- **نموذج قراءة واحد للمالك فوق الجدولين الموجودين**، لا جدول ثالث ولا عمود `visibility`: لا تكرار بيانات، ولا مسار كتابة جديد، ولا هجرة، ويسري على ما سُجّل سابقاً فوراً.
- سجل المالك = `admin.owner_audit_log` (إجراءاته على صفحة `/owner`) ∪ `admin.admin_activity_log` حيث `actor_id` مقعد مالك (إجراءاته داخل أدوات المشرفين).
- **العزل في SQL لا في الواجهة**: يُستبعد `actor_id IN (SELECT user_id FROM admin.platform_owners)` من `GET /admin/audit` ومن «سجل المشرفين» عند المالك. إخفاء التبويب في التطبيق طبقة ثانية فقط.
- العزل بـ`admin.platform_owners` لا `admin.active_owners`: يبقى صحيحاً لو عُطّل المقعد أو أُلغي.
- **التنازل المعلن**: إجراء المالك داخل أدوات المشرفين يُعرض في سجله بـ«ماذا/أين/متى/النتيجة» دون «السبب» النصي (يبقى محفوظاً في `admin.audit_log`). عرض السبب بند منفصل لاحق، ليس شرطاً هنا.
- لا هجرة (آخر هجرة في الشجرة 0226، والتالية 0227 غير مستعملة)، لا جداول ولا أعمدة ولا صلاحيات، لا تبعيات.
- لا تغيير في شكل أي DTO قائم (يتغير محتوى `GET /admin/audit` بالاستبعاد لا شكله)، ولا في `ownerGate` ولا `bearerAuth` ولا مسارات الكتابة. لا `isOwner` في الطلب الساخن.
- لا كشف لأي صف من `owner_audit_log` أو من صفوف المالك في `admin_activity_log` عبر مسار غير `/owner/audit`.
- كل سكربت يسمّي ملفاته في رأسه، وما لم يُسمَّ فيه يعني توقفاً. الخادم قبل التطبيق. سكربت واحد في كل رد، يُرسَل فور اكتماله.
- `AppTokens` فقط في الواجهة، `Result`/`AppError`، والنصوص العربية مباشرة في تبويبات المالك (لا مفاتيح ARB جديدة).

## 3. حقائق مؤكدة من الشجرة (وما يخالف الخطة الأصلية)

- `admin.owner_audit_log` (هجرة 0219): `id bigint`, `actor_id`, `method` (POST/PUT/PATCH/DELETE)، `path` (يبدأ بـ`/owner/`)، `status`, `occurred_at`، وفهرس `(occurred_at desc, id desc)`. يكتبه `ownerGate` (`apps/server/lib/http/owner_gate.dart`) عبر المنفذ `OwnerAuditLog`، ولا يقرؤه أحد اليوم.
- `admin.admin_activity_log` (هجرة 0224): نفس الأعمدة، ومعه `PostgresAdminActivityLog.latestSql` (يضم اسم الفاعل والهدف والنتيجة من مسار الطلب). و`admin.platform_owners (user_id)` من 0217.
- `PostgresAuditLogRepository._listSql` عند السطر 91 من `postgres_audit_log_repository.dart`: `FROM admin.audit_log ORDER BY occurred_at DESC, id DESC`.
- النموذج الجاهز للنسخ: `OwnerAdminActivity` (اسم الملف الفعلي `packages/application/lib/src/admin/owner_admin_activity.dart`، **وليس** `list_owner_admin_activity.dart` كما في الخطة الأصلية)، والمسار `apps/server/routes/owner/admin-activity/index.dart`، والـDTO في `packages/contracts/lib/src/admin_activity_dto.dart` (**وليس** `admin_activity_log_dto.dart`)، و`AdminApi.ownerAdminActivity()`، و`owner_admin_activity_section.dart` (فيه `adminActivityLabel(method, path)` عامة).
- `composition_root.dart`: حقل `ownerAdminActivity` عند الأسطر ~218 و~468 و~2843، وتركيبه في bootstrap عند ~3801، و`_absentListAuditLog()` عند ~1983 نمطاً لبدائل `forTesting`.
- قائمة تبويبات المالك في `OwnerGeneralSection` داخل `admin_shell.dart` (ثمانية تبويبات اليوم، `columns: 4`)؛ التاسع يجعلها ثلاثة صفوف، فتحقق من أي اختبار يعدّ التبويبات.
- اختبارات قائمة يُقاس عليها: `packages/infrastructure/test/admin/` (`postgres_admin_activity_log_test.dart`، `postgres_owner_audit_log_test.dart`، `postgres_admin_repositories_test.dart`، `postgres_admin_repositories_integration_test.dart` DB-gated)، `packages/application/test/admin/` (`list_audit_log_test.dart`، `owner_*_test.dart`)، `apps/server/test/http/admin_activity_test.dart` و`owner_gate_test.dart` و`apps/server/test/routes/`، `packages/api_client/test/`، `apps/mobile/test/features/admin/owner_admin_activity_section_test.dart`.
- **دروس هذه الجلسة**: (أ) سكربتات الواجهة تُشغّل أيضاً `apps/mobile/test/audit/` (كشف 338 مخالفة لون نص `t.primary` بدل `t.primaryText` لم يظهر في 335)؛ (ب) لا `Row` بـ`crossAxisAlignment.stretch` داخل تمرير بلا حدّ ارتفاع (لفّه بـ`IntrinsicHeight`)؛ (ج) قراءة سبب الفشل من السجل: `grep -a -A4 -E "\[E\]|gained|The following .* was thrown" "$(ls -t /sdcard/Download/<NAME>_*.log | head -1)" | grep -av -E "^#[0-9]|asynchronous suspension" | head -40`.

## 4. التصميم

**سطر السجل** `OwnerAuditLine`: `source` (`'owner'` أو `'admin'`)، `id`, `actorName`, `method`, `path`, `at`، و`target`/`result` اختياريان. الـ`source` ضروري لأن `bigint` في الجدولين مستقل فلا يكفي `id` وحده في المفاتيح ولا في كسر التعادل.

**الاستعلام** (`PostgresOwnerAuditReader.latest`، قراءة فقط، بلا فهرس جديد):

```sql
WITH lines AS (
  SELECT 'owner'::text AS source, l.id,
         coalesce(u.display_name, '') AS actor_name,
         l.method, l.path, l.occurred_at,
         NULL::text AS target, NULL::text AS result
  FROM admin.owner_audit_log l
  JOIN identity.users u ON u.id = l.actor_id
  UNION ALL
  SELECT 'admin'::text, l.id, coalesce(a.display_name, ''),
         l.method, l.path, l.occurred_at,
         coalesce(u.display_name, fs.home_team || ' × ' || fs.away_team),
         CASE WHEN fr.fixture_id IS NULL THEN NULL
              ELSE fr.home_goals::text || '-' || fr.away_goals::text END
  FROM admin.admin_activity_log l
  JOIN identity.users a ON a.id = l.actor_id
  JOIN admin.platform_owners o ON o.user_id = l.actor_id
  LEFT JOIN LATERAL ( ...نفس regexp_match لـlatestSql... ) t ON true
  LEFT JOIN identity.users u ON u.id = t.id
  LEFT JOIN competition.fixture_schedules fs ON fs.fixture_id = t.id
  LEFT JOIN scoring.fixture_results fr ON fr.fixture_id = t.id
)
SELECT * FROM lines ORDER BY occurred_at DESC, source, id DESC LIMIT @limit;
```

**العزل**: سطر واحد قبل `ORDER BY` في `_listSql`: `WHERE actor_id NOT IN (SELECT user_id FROM admin.platform_owners)`، ومثله `WHERE l.actor_id NOT IN (...)` في `latestSql` قبل `ORDER BY`.

**المسار** `GET /owner/audit`: GET فقط وإلا 405؛ `root.listOwnerAudit == null` يعيد `AppError.transient('owner.audit_unavailable', ...)`؛ لا فحص صلاحية في المسار (`ownerGate` يضمن المقعد، و`ListOwnerAudit` يعيد الفحص: `requireRole(admin)` ثم `isOwner` وإلا `admin.owner_only`، و`limit` مقيّد بين 1 و200). أي غير مقعد يرى 404 «Route not found» نفسه.

**الواجهة**: تبويب «سجلي» بعد «سجل المشرفين»: ترويسة «سجلي» / «كل ما فعلته أنت: ماذا، وأين، ومتى. لا يراه مشرف ولا لاعب.»، كل سطر بـ`adminActivityLabel` ثم الهدف والوقت وشارة المصدر («صفحة المالك» أو «أدوات المشرفين»)، `RefreshIndicator`، مفاتيح `owner.audit.list` و`owner.audit.item.$source.$id` وحالات التحميل والفراغ والخطأ كنمط `owner_admin_activity_section.dart`.

## 5. جدول المتابعة

الخادم أولاً: سطح القراءة (340 إلى 343) قبل العزل (344 و345)، حتى لا يفقد المالك رؤية سجله لحظة تختفي صفوفه من سجل المشرفين (لا صف يُحذف في أي حال).

| # | السكربت | الملفات | الحالة |
|---|---|---|---|
| 339 | حفظ هذه الخطة في المستودع (وثائق فقط) | docs/handoff/owner-audit-plan.md, docs/checkpoints/session-log.md | تم |
| 340 | العقد: `OwnerAuditEntryDto` و`OwnerAuditLogDto` (`schema_version` 1، snake_case، على نمط `admin_activity_dto.dart`) وتصديرهما | packages/contracts/lib/src/owner_audit_log_dto.dart (جديد), packages/contracts/lib/contracts.dart, packages/contracts/test/owner_audit_log_dto_test.dart (جديد) | تم |
| 341 | التطبيق: منفذ القراءة `OwnerAuditReader` و`OwnerAuditLine` (منفصل عن منفذ الكتابة `OwnerAuditLog`) وحالة الاستخدام `ListOwnerAudit` وتصديرهما | packages/application/lib/src/admin/ports/owner_audit_reader.dart (جديد), packages/application/lib/src/admin/list_owner_audit.dart (جديد), packages/application/lib/application.dart, packages/application/test/admin/list_owner_audit_test.dart (جديد) | تم |
| 342 | البنية: `PostgresOwnerAuditReader` بالاستعلام أعلاه، صف تالف → `transient`، وتصديره | packages/infrastructure/lib/src/admin/postgres_owner_audit_reader.dart (جديد), packages/infrastructure/lib/infrastructure.dart, packages/infrastructure/test/admin/postgres_owner_audit_reader_test.dart (جديد) | تم (commit b92442e7) |
| 343 | الخادم: حقلا `ownerAuditReader` و`listOwnerAudit` في الجذر (bootstrap وبدائل `forTesting` بـ`_UnwiredOwnerAuditReader` يرمي `StateError`) والمسار `GET /owner/audit` | apps/server/lib/composition/composition_root.dart, apps/server/routes/owner/audit/index.dart (جديد), apps/server/test/routes/owner_audit_route_test.dart (جديد) | تم (commit 12eb15e1) |
| 344 | العزل 1: استبعاد مقاعد المالك من `GET /admin/audit` في `_listSql`، مع اختبار قاعدة DB-gated (صفّان، يعود صف المشرف وحده) | packages/infrastructure/lib/src/admin/postgres_audit_log_repository.dart, packages/infrastructure/test/admin/postgres_admin_repositories_test.dart, packages/infrastructure/test/admin/postgres_admin_repositories_integration_test.dart | تم (commit 7a969322) |
| 345 | العزل 2: استبعاد مقاعد المالك من `latestSql` (سجل المشرفين عند المالك للمشرفين وحدهم)، وتحديث `supabase/tests/0224_admin_activity_log_test.sql` إن كان ينسخ نص الاستعلام | packages/infrastructure/lib/src/admin/postgres_admin_activity_log.dart, packages/infrastructure/test/admin/postgres_admin_activity_log_test.dart, supabase/tests/0224_admin_activity_log_test.sql (إن لزم) | تم (commit 702f16e4) |
| 346 | العميل: `AdminApi.ownerAudit()` على `/owner/audit`، والفشل يعود `Err` | packages/api_client/lib/src/admin_api.dart, packages/api_client/test/owner_audit_api_test.dart (جديد) | تم (commit 3a945e57) |
| 347 | التطبيق: `OwnerAuditSection` وتبويب «سجلي» في `OwnerGeneralSection`؛ اختبار بـ`ProviderScope` override (لا Mock للشاشة)، وغياب المقعد يخفي القسم؛ يُشغّل أيضاً `test/audit/` | apps/mobile/lib/features/admin/screens/sections/owner_audit_section.dart (جديد), apps/mobile/lib/features/admin/admin_shell.dart, apps/mobile/test/features/admin/owner_audit_section_test.dart (جديد) | - |
| 348 | التوثيق الختامي: `docs/remediation-plan.md` قسم 6.6 جديد بعد 6.5 (طلب «سجل تدقيق المالك، معزول» تم)، وقسم جديد في `docs/project-context.md` بعنوان `The owners' own audit log, read at last (scripts 340-347, 2026-11-26)` يذكر المسار والمصدرين و`source` وموضعَي الاستبعاد وأن `admin.audit_log` لم يُمسّ صفّه ولا هجرة | docs/remediation-plan.md, docs/project-context.md, docs/checkpoints/session-log.md | - |

الاختبارات المطلوبة عبر السكربتات (نقاط دخول حقيقية): (1) طلب `GET /owner/audit` بمقعد مالك = 200 بسطور من المصدرين، وبمشرف بلا مقعد أو لاعب أو رمز فاسد = 404 «Route not found»، و405 لغير GET (343)؛ (2) قاعدة: `PostgresAuditLogRepository.list` لا يعيد صف مقعد مالك (344)؛ (3) قاعدة: `PostgresOwnerAuditReader.latest` يعيد صفوف المالك من الجدولين فقط، مرتبة، بـ`source` صحيح، ولا يعيد صف مشرف (342)؛ (4) واجهة: التبويب وسطراه المصدران، وغياب المقعد يخفيه (347).

## 6. قالب كل سكربت

حراس (المستخدم dev، الفرع main، شجرة نظيفة، وعلامة `NKxxx_` غير موجودة، ووجود مرساة السكربت السابق) ثم رقعة بايثون `str.replace` مرمّزة base64 على سطر واحد، مع trap للتراجع، ثم `dart format` للملفات المعدلة، `dart analyze --fatal-warnings .`، `import_lint`، الاختبارات المتأثرة، فحص النطاق (`git diff --name-only` ضمن قائمة السكربت)، ثم commit بأسماء الملفات. لا `git add -A`، لا push. في الختام سطر في `docs/checkpoints/session-log.md` ويُذكر رقم التالي.

## 7. التراجع وحدود الخطة

- التراجع: `git revert --no-edit <sha>` لكل سكربت. لا شيء في قاعدة البيانات ليُرجَع. رجوع 344 و345 يُعيد ظهور صفوف المالك للمشرفين تلقائياً.
- لا تُنشئ الخطة جدولاً ولا عموداً ولا هجرة، ولا تعرض «سبب» إجراء المالك، ولا تمسّ صلاحيات المشرفين، ولا تعالج إجراءات المالك لاعباً (توقعات، مجموعات)، ولا السجلات القديمة الناقصة من سكربتات 217 إلى 248 (توثيق مستقل).
