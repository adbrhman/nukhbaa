# نقطة توقف — بعد 7.10 الجزئي (commit 3e8f3ef)

## آخر ما أُنجز
- **7.8** ✅ commit 566eedd — حذف RoundOpenController/RoundLockController + openRound/lockRound + OpenRoundRequestDto من الموبايل/contracts.
- **7.9** ✅ commit 982ea8f — حذف roundLeaderboard الميت من الموبايل، استرجاع adminRoundOptionLabel (كانت محذوفة خطأً)، حذف KPI يتيم.
- **7.10 (جزئي)** ✅ commit 3e8f3ef — حذف CompetitionApi.getRoundReport (بلا مستهلك) و RoundReportSummaryController بالكامل (بلا مستهلك؛ فقط RoundReportController الفعلي — يدمج adminGetRoundScores + adminListRoundPredictions — مستخدَم من results_scoring_section.dart).

## اكتشاف حاسم يُلغي افتراض خريطة الاعتماديات الأصلية (Phase 7.1)
خريطة "الملفات المرشحة للحذف لاحقًا" (القسم 12 من التحليل الأصلي) افترضت أن كامل طبقة Round (server routes + application use-cases + domain) هي Legacy قابلة للحذف الكامل في 7.10. **هذا غير صحيح فعليًا.** الفحص بالـgrep الآن يُظهر أن معظم دوال Round في competition_api.dart لا تزال مستهلَكة من شاشات حية فعلية:
- listSeasonRounds, getRound, browseRoundFixtures → competition_providers.dart (تصفح)
- linkFixtureToRound, removeFixtureFromRound → admin_providers.dart (إدارة ربط المباريات بالجولات، لا تزال جزءًا من تدفق الإدارة الحالي عبر admin_pickers.dart / fixture_schedule_section.dart)
- scoreRound → results_scoring_section.dart (تسجيل النقاط)
- postRoundToLedger → admin_providers.dart (الليدجر)
- getRoundScores → round_scores_providers.dart (تاريخ النقاط)
- adminGetRoundScores + adminListRoundPredictions (AdminApi) → RoundReportController (تقرير الجولة الفعلي في results_scoring_section.dart)

فقط دالتان كانتا كودًا ميتًا حقيقيًا: getRoundReport (CompetitionApi) و RoundReportSummaryController — تم حذفهما.

## الخلاصة/القرار المطلوب قبل أي حذف إضافي في 7.10
**"Legacy Round cleanup الكامل" كما صيغت في الخطة الأصلية لم تعد قابلة للتنفيذ كما هي.** إدارة المباريات (ربط Fixture بـRound عبر admin_pickers.dart) والتسجيل والنقاط والليدجر لا تزال تعتمد معماريًا على Round بشكل حي وحقيقي في تجربة الإدارة الحالية — وهذا يطابق فعليًا ما ورد في القسم 5 من التحليل الأصلي (fixture_schedule_section.dart لا يزال مربوطًا بـRound) لكنه يتناقض مع افتراض القسم 12/11 بأن هذا الربط "Legacy" جاهز للحذف.
القرار المطلوب من المستخدم في الجلسة القادمة: إما (أ) الانتقال أولًا لإعادة تصميم إدارة المباريات لتصبح مرتبطة بالموسم مباشرة بدل Round (بند 11.3 من التحليل الأصلي: fixture_schedule_section.dart redesign) — وعندها فقط يصبح حذف طبقة Round ممكنًا فعليًا، أو (ب) الإبقاء على النظامين المتوازيين معًا وإغلاق 7.10 كمهمة "تنظيف الكود الميت المعزول فقط" (وهو ما أُنجز بالفعل الآن).

## الاختبارات
- flutter analyze: نظيف
- flutter test: 107/107 ناجح

## دروس منهجية (تراكمية من الجلسات السابقة)
- استخدم `flutter pub run build_runner build` وليس `dart run build_runner build`.
- بعد أي حذف من ARB: flutter gen-l10n ثم build_runner فورًا، وإلا تختفي الأخطاء الحقيقية عن flutter analyze.
- قبل حذف أي دالة/كلاس "يبدو Round-legacy": ابحث بأسماء الدوال الفعلية (grep دقيق)، ليس بأنماط عامة — نمط عام قد يرجع فارغًا خطأً بينما الدالة مستخدمة فعليًا باسم مختلف (مثال: AdminApi.adminGetRoundReport مقابل CompetitionApi.getRoundReport).
- ملفات *.g.dart مستثناة من git (.gitignore) — طبيعي ألا تظهر في git status.

## القرارات المؤجَّلة (لم تُمس، من الجلسات السابقة)
- score_round.dart / RulesetSnapshot المجمَّد — خارج النطاق، بند تصميم منفصل.
- score_fixture doubling bug — بند إصلاح مستقل يحجب Phase 7.7.
- notification_kind_test.dart — تحديث بسيط لعدد enum values (4 بدل 3).
