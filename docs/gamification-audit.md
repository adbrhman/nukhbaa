# جرد ما هو قائم قبل التلعيب (P0-1)

_تاريخ الجرد: 2026-09-19. المصدر: `supabase/migrations` (51 ملفاً، 0001–0051)
و`packages/domain` و`packages/application`. هذا الملف هو مخرَج المهمة P0-1
من خطة التلعيب، والبوابة التي تُقرّر أيّ مهام P0 الباقية لازمة فعلاً._

---

## 1. الخلاصة التنفيذية

ثلاث مهام من المرحلة 0 **منجزة أصلاً** في المستودع، وتنفيذها كما وُصفت في
الخطة يُنشئ نسخة ثانية من بنية قائمة — وهو تحديداً خطر «مسار الاحتساب
المزدوج» الذي عولج مرة في هجرة الأكسيوم الرابع.

| مهمة الخطة | الحكم |
|---|---|
| P0-1 جرد | هذا الملف |
| P0-2 `gamification_events` | **جديدة** — لا مقابل لها |
| P0-3 `points_ledger` | **موجودة** بالكامل: `ledger.fixture_point_entries` |
| P0-4 `user_points_summary` | **أُلغيت** — انظر §8 |
| P0-5 محرك قواعد بـ`rule_version` | **موجودة**: `ScoringRuleset.rulesetVersion` |
| P0-6 ربط التسجيل بالنتيجة | **موجودة**: `PostFixtureToLedger` |
| P0-7 أعلام الميزات | **نُفِّذت**: هجرة 0054 |
| P0-8 واجهات KPI | **نُفِّذت جزئياً**: هجرة 0054، انظر §8 |

---

## 2. المخططات والجداول القائمة

31 جدولاً عبر عشرة مخططات:

- `identity` — `users` (المفتاح هو subject UUID من Supabase Auth)، `avatar_reports`
- `competition` — `competitions`, `seasons`, `rounds`, `participants`,
  `fixture_schedules`, `season_fixtures`, `round_fixtures`
- `prediction` — `fixture_predictions`, `predictions`, `prediction_scores`
- `scoring` — `fixture_results`, `fixture_scores`, `round_scores`,
  `round_score_fixtures`
- `ledger` — `fixture_point_entries`, `point_entries`
- `leaderboard` — `season_rank_snapshots`
- `notification` — `device_tokens`, `reminder_sends`, `notifications`,
  `announcements`
- `social` — `fixture_reactions`, `reactions`
- `football_data` — `teams`, `leagues`, `fixtures`, `fixture_results`,
  `external_identity_map`, `sync_runs`
- `admin` — `audit_log`

---

## 3. دفتر النقاط — لماذا لا يُنشأ ثانٍ

`ledger.fixture_point_entries` (هجرة 0020) هو مصدر النقاط الوحيد:

```
id, participant_id, fixture_id, entry_kind, amount, source_ref,
occurred_at, created_at, updated_at
constraint fixture_point_entries_fixture_score_uniq
  unique (participant_id, fixture_id, entry_kind, source_ref)
```

- **إضافي فقط (append-only)**: التصحيح يتم بقيد `adjustment` موجب أو سالب،
  لا بتعديل صف قائم. `EntryKind` في `packages/domain/lib/src/ledger/`
  يضم `roundScore` و`fixtureScore` و`adjustment`.
- **منع الاحتساب المزدوج قائم**: القيد الفريد أعلاه هو بالضبط ما تطلبه
  P0-3 عبر `(event_id, reason)`. المحوّل يعتمد على اسم القيد لتحويل
  التضارب إلى لا-عملية.
- **الربط بالنتيجة قائم**: `PostFixtureToLedger` يُستدعى عند اعتماد النتيجة
  النهائية، وهو ما تطلبه P0-6.

**القرار المقترح:** تُلغى P0-3 و P0-6. أي نوع نقاط جديد (تحدٍ يومي، بونص
سلسلة، شارة) يُضاف كقيمة جديدة في `ledger.entry_kind` وقيد في الدفتر نفسه،
بمفتاح `source_ref` يحمل معنى الحدث. دفتران = ترتيبان متضاربان.

> تحذير تشغيلي من 0020: PostgreSQL يرفض استخدام قيمة enum في المعاملة
> نفسها التي أضافتها (SQLSTATE 55P04). أي `alter type ledger.entry_kind
> add value` يجب أن يكون في هجرة منفصلة عن الجدول/القيد الذي يستعملها.

---

## 4. ما تطلبه الخطة وهو منجز خارج المرحلة 0

- **قاعدة الإقفال عند صافرة البداية** — منفَّذة في
  `SubmitFixturePrediction` (القاعدة 3): يُقرأ `FixtureSchedule.kickoffAt`
  ويُقاس بـ`FixtureLock.at`؛ ومباراة بلا وقت انطلاق مسجَّل تُرفض بدل أن
  تُترك مفتوحة. لا حاجة لعمل جديد هنا.
- **توقع واحد لكل (مشارك، مباراة)** — قيد فريد في
  `prediction.fixture_predictions`، والمحوّل يحوّل خسارة سباق الإدراج إلى
  تعديل.
- **الإشعارات (جزء من P3)** — `notification.device_tokens` (0039) يحمل
  رموز FCM، و`notification.reminder_sends` (0040) مفتاحه
  `(user_id, reminder_date)` وهو ما يجعل تكرار نبضة المجدول لا-عملية.
  المسار مبني ويعمل على جهاز حقيقي. يبقى من P3-2 جديداً:
  `notification_preferences` و`notification_queue` وساعات الهدوء والسقف
  الأسبوعي.

---

## 5. ما هو ناقص فعلاً

| ناقص | يخدم |
|---|---|
| سجل أحداث موحَّد (`gamification_events`) | P0-2، وكل محرك مدفوع بالحدث بعده |
| `rule_version` على قواعد النقاط | P0-5 |
| محرك السلسلة وعرضها وبونصها | P1 (الإكمال اليومي مسجَّل) |
| كل جداول الشارات والدوري الأسبوعي | P2 |
| تفضيلات الإشعارات وطابورها | P3 |
| جداول/عروض الدقة والرؤى | P4 |
| أعلام الميزات وتعيينات التجربة | P0-7 |

---

## 6. تعارض معماري يحتاج قراراً

الخطة تفترض `pg_cron` أو وظائف حافة (Edge Functions) للوظائف الدورية.
المجدول القائم في المشروع يعيش في خادم Dart Frog
(`apps/server/lib/scheduler/provider_sync_scheduler.dart`) على Northflank،
ويستعمل `football_data.sync_runs` (0051) كحارس تكرار.

الخياران غير متكافئين: خادم الحاوية يمكنه استدعاء حالات الاستخدام في
`packages/application` مباشرة، بينما `pg_cron` يفرض تكرار قواعد العمل في
SQL — وهو ما يناقض المبدأ الثالث في الخطة نفسها («المنطق في Dart»).

**الاقتراح:** كل وظيفة دورية جديدة تسكن المجدول القائم، بنفس نمط
`sync_runs` للـidempotency. يبقى `pg_cron` للقطات الترتيب اليومية فقط،
وهي قرار سابق مستقل.

---

## 7. قرار الردم

**محسوم 2026-09-19:** التلعيب يبدأ من تاريخ تفعيل النظام بـ
`rule_version = 1`. لا احتساب رجعي من توقعات ما بعد 2026-09-05، ولا صفوف
تاريخية في `gamification.events`.

---

## 8. ما نُفِّذ فعلاً من المرحلة 0، وما أُلغي

**نُفِّذ:**

- **P0-2** — هجرة 0053: مخطط `gamification`، جدول `events` إضافي فقط،
  حارس يرفض UPDATE وDELETE لكل الأدوار، `dedupe_key` فريد، RLS بقراءة
  ذاتية فقط. لا يحمل نقاطاً: `amount` غائب عمداً.
- **الشريحة العمودية لـP0-2** — `GamificationEventType` و`GamificationEvent`
  و`GamificationEventId` في المجال، `GamificationEventSink` منفذاً،
  `PostgresGamificationEventSink` محوّلاً، وأول باعث حقيقي
  (`prediction_placed`) في `SubmitFixturePrediction`. المنفذ اختياري
  وTier-3: فشل كتابة الحدث لا يُفشل التوقع، والمفتاح الفريد يجعل الحدث
  الضائع قابلاً لإعادة البثّ.
- **P0-7** — هجرة 0054: `feature_flags` و`experiment_assignments`. خلفية
  فقط، بلا أي سياسة للعميل: العميل يتلقّى سلوكاً لا إعداداً، وعميل لا
  يقرأ ذراعه لا يستطيع اختيارها.
- **P0-8 جزئياً** — هجرة 0054: `daily_active_users` وحده. المشاهدتان
  الأخريان (`challenge_completion_rate`، `streak_participation`) تقرآن
  جداول لم تُنشأ بعد؛ عرضٌ فوق أعمدة غير موجودة وعدٌ لا قياس، فتأتيان مع
  جداول المرحلة 1.

**أُلغي — P0-4 `user_points_summary`:**

الترتيب والأرصدة تُشتق اليوم من `ledger.*` وتُلتقط في
`leaderboard.season_rank_snapshots`. جدول ملخّص ثالث يعني مصدر ترتيب
ثالثاً يحتمل أن يخالف الاثنين. إن ظهر بطء قياس في الشاشات فالعلاج فهرس أو
عرض مُجسَّد (materialized view) فوق الدفتر، لا نسخة ثالثة من الحقيقة.

**كان منجزاً سلفاً — P0-5:**

`ScoringRuleset` يحمل `rulesetVersion` ويُقرأ من `RulesetSnapshot` مجمَّد
عند الإنشاء (`competition.rounds.ruleset_snapshot`). تغيير القواعد
مستقبلاً إصدارٌ جديد لا تعديل تاريخي — وهو نصّ ما تطلبه المهمة.

**خلاصة: المرحلة 0 مغلقة.** البوابة التالية هي المرحلة 1 (التحدي اليومي
والسلاسل)، وأول ما تحتاجه عمود المنطقة الزمنية على `identity.users`
(P1-1) — أُنجز في هجرة 0055 مع المسار الذي يملؤه.

**محسوم 2026-09-19 (حدّ اليوم):** السلسلة والتحدي اليومي وعروض المؤشرات
تُحسب بيوم الرياض، وهو اليوم نفسه الذي تستعمله مزامنة المباريات والنتائج
و`reminder_sends`. يوم واحد مشترك يعني مجموعة مباريات واحدة وجدول ترتيب
واحد. `identity.users.utc_offset_minutes` يخدم توقيت الإشعار على ساعة
القارئ (ساعات الهدوء، P3-2) ولا يُشتقّ منه أي حدّ يوم.
