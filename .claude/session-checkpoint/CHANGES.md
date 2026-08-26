# سجل التغييرات الفعلية — مشروع نُخبة

## قبل اعتماد ترتيب Phase 7 الرسمي
- إصلاح باگ JWKS (jwks_client.dart) — نقص minRefreshInterval في تست الـrotation — commit `90222ef`
- إصلاح فشل CI في admin_routes_test.dart / ledger_routes_test.dart بسبب dedupe على round_score — إضافة kRoundId2
- إصلاح ARB تالف (app_en.arb) — حذف heredoc غير مغلق سابقًا

## Phase 7.8 — commit `566eedd`
- حذف round_administration_section.dart بالكامل
- حذف RoundOpenController/RoundLockController من admin_providers.dart
- حذف استدعاءات من admin_sections.dart, admin_shell.dart
- حذف openRound()/lockRound() من competition_api.dart
- حذف OpenRoundRequestDto من contracts
- تنظيف مفاتيح ARB مرتبطة (ar/en)
- النتيجة: 107/107 تست ناجح، flutter analyze نظيف

## Phase 7.9 — commit `982ea8f`
- حذف roundLeaderboard provider + 3 مفاتيح ARB من الموبايل (كود ميت من جهة العميل فقط)
- استرجاع adminRoundOptionLabel (كانت محذوفة خطأً في 7.8 رغم استخدامها الحي في admin_pickers.dart)
- حذف سطر KPI يتيم (adminRoundsTab) من admin_hub_screen.dart
- النتيجة: 107/107 تست ناجح، flutter analyze نظيف

## Phase 7.10 (جزئي فقط) — commit `3e8f3ef`
- حذف CompetitionApi.getRoundReport (بلا مستهلك)
- حذف RoundReportSummaryController بالكامل (بلا مستهلك)
- اكتشاف: معظم دوال Round (listSeasonRounds, getRound, browseRoundFixtures, linkFixtureToRound, removeFixtureFromRound, scoreRound, postRoundToLedger, getRoundScores) لا تزال مستهلَكة فعليًا — إكمال 7.10 الحقيقي مؤجَّل حتى تنتهي 7.4

## Phase 7.4 — لا commit جديد بعد (تحليل/قرارات فقط)
- 7.4.1 تحليل الاعتماديات: مكتمل — الفجوة الوحيدة: لا يوجد مسار INSERT لـSeasonFixture
- القرارات المعمارية المعتمدة: linkFixtureToSeason يُضاف إلى FixturePredictionRepository الحالي، route يبقى POST /seasons/{id}/fixtures بدون تغيير بنية الروتس
- 7.4.2 DB/RLS: مكتمل — لا حاجة لأي migration (الخادم يتصل بدور postgres جذري يتجاوز RLS أصلًا)
- 7.4.3 (التالي): LinkFixtureToSeason use-case + توسعة الـrepository port — لم يبدأ بعد
