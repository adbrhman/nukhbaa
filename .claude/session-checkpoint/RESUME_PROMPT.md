# نقطة استكمال جاهزة — مشروع نُخبة

اقرأ أولًا: .claude/session-checkpoint/SESSION_STATE.md و CHANGES.md في هذا الريبو، ثم تحقق من git log و git status فعليًا قبل أي عمل — لا تفترض شيء من الذاكرة.

## الوضع الحالي بالضبط
- آخر commit مدفوع: `3e8f3ef` (Phase 7.10 الجزئي)
- المرحلة الحالية: Phase 7.4 — Season-based Fixture Administration
- آخر خطوة فرعية مكتملة: 7.4.2 (DB/RLS) — أُغلقت بلا أي migration جديدة (الخادم يتصل بدور postgres جذري privileged يتجاوز RLS بالكامل)
- الخطوة التالية المعلَّقة: **7.4.3 — LinkFixtureToSeason use-case + توسعة FixturePredictionRepository** — لم تبدأ، بانتظار أمر صريح

## القرارات المعمارية النهائية لـ7.4 (لا تُعاد المناقشة، نُفِّذ كما هي)
- linkFixtureToSeason({required SeasonId seasonId, required FixtureId fixtureId}) يُضاف إلى FixturePredictionRepository الحالي — بدون repository جديد
- Server route: POST /seasons/{id}/fixtures (نفس مسار GET الحالي حرفيًا، بلا تغيير بنية الروتس، بلا competitionId في الـURL)
- ترتيب التحقق داخل use-case: admin role → Season موجود → قراءة competitionId → Fixture موجود → منع duplicate → حساب displayOrder → تنفيذ الربط → DTO بنفس conventions الـGET
- ممنوع لمسه في 7.4: Round, RoundFixture, LinkFixtureToRound, RemoveFixtureFromRound, ScoreRound, PostRoundToLedger, GetRoundScores, RoundPickerField, competition.rounds, competition.round_fixtures

## الترتيب الفرعي المتبقي لـ7.4
7.4.3 use-case+port → 7.4.4 Postgres impl+tests → 7.4.5 server route+DTO+tests → 7.4.6 API client → 7.4.7 mobile (fixture_schedule_section + AddMatchController) → 7.4.8 verification كاملة

## قواعد إلزامية طوال العمل
لا تجاوز مرحلة فرعية، دفعات صغيرة قابلة للتحقق، لا commit تلقائي أبدًا، توقف وأرسل تقرير بعد كل خطوة فرعية، توقف فورًا عند فشل أي تست، افحص الملف الفعلي قبل أي تعديل (لا افتراض أسماء/signatures)، لا تغيير business logic أو Supabase/Auth/API architecture خارج نطاق 7.4.3 تحديدًا.

## بيئة العمل
الجذر: /home/dev/nukhbaa-backup-1787537565 (عبر proot-distro login ubuntu ثم su - dev)، ريبو github.com/adbrhman/nukhbaa فرع main.
