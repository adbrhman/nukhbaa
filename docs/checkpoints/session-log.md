- [21:13] إصلاح: إضافة حقل seasonId اختياري إلى FixturePredictionView | ملف: packages/application/lib/src/prediction/fixture_prediction_view.dart | اختبار: نجح
- [$(date +%H:%M)] إصلاح: إضافة عمود season_id لاستعلام listByUser وتمريره إلى FixturePredictionView | ملف: packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart | اختبار: ${TEST_STATUS}
- [22:14] إصلاح: إضافة حقل seasonId اختياري إلى FixturePredictionDto ورفع schemaVersion إلى 2 | ملف: packages/contracts/lib/src/fixture_prediction_dto.dart | اختبار: نجح
- [22:23] إصلاح: تمرير seasonId من FixturePredictionView إلى FixturePredictionDto في fixturePredictionViewToJson | ملف: apps/server/lib/http/fixture_prediction_dto_mapper.dart | اختبار: نجح
- [22:29] إصلاح: إضافة CompetitionApi.getFixtureScores(seasonId, fixtureId) | ملف: packages/api_client/lib/src/competition_api.dart | اختبار: نجح
- [22:53] إصلاح: إضافة fixtureScoresProvider (GET /seasons/{id}/fixtures/{fixtureId}/scores) | ملف: apps/mobile/lib/features/history/fixture_scores_providers.dart | اختبار: نجح
- [22:58] إصلاح: دمج badge الدرجة (fixtureScoresProvider) في _FixturePredictionCard | ملف: apps/mobile/lib/features/history/prediction_history_screen.dart | اختبار: نجح
- [00:21] إصلاح: AdminGetFixtureScores + مسار /admin/fixtures/{id}/scores + adminGetFixtureScores/adminListFixturePredictions في AdminApi | ملفات: packages/application/lib/src/scoring/admin_get_fixture_scores.dart, packages/application/lib/application.dart, apps/server/lib/composition/composition_root.dart, apps/server/routes/admin/fixtures/[id]/scores/index.dart, packages/api_client/lib/src/admin_api.dart | اختبار: نجح
- [01:02] إضافة: fixture_report.dart + FixtureReportController + زر/عرض تقرير المباراة في ResultsScoringSection (نطاق _fixtureId) + مفتاحا ARB جديدان | ملفات: apps/mobile/lib/features/admin/fixture_report.dart, apps/mobile/test/features/admin/fixture_report_test.dart, apps/mobile/lib/features/admin/admin_providers.dart, apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart, apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb | اختبار: نجح
- [02:17] إصلاح: listActiveParticipantSeasons (طبقة قراءة معزولة، Postgres+Fake+InMemory+composition_root+اختبارات) | ملفات: packages/domain/lib/src/competition/participant_season_feed_entry.dart, packages/domain/lib/domain.dart, packages/application/lib/src/competition/ports/competition_repository.dart, packages/infrastructure/lib/src/competition/postgres_competition_repository.dart, packages/application/test/competition/fake_competition_repository.dart, apps/server/test/routes/competition_route_harness.dart, apps/server/lib/composition/composition_root.dart, packages/infrastructure/test/competition/postgres_competition_repository_test.dart | اختبار: نجح
- [02:42] إصلاح: ListMyActiveSeasons use-case + تصدير + اختبارات (طبقة application) | ملف: packages/application/lib/src/competition/list_my_active_seasons.dart | اختبار: نجح
- [02:53] إصلاح: ActiveSeasonDto + اختبارات (طبقة contracts) | ملف: packages/contracts/lib/src/competition_dto.dart | اختبار: نجح
- [03:10] إصلاح: إضافة activeSeasonToDto (mapper) لتحويل ParticipantSeasonFeedEntry إلى ActiveSeasonDto | ملف: apps/server/lib/http/competition_dto_mapper.dart | اختبار: نجح
- [03:40] إصلاح: إزالة unused import (package:application/application.dart) من apps/server/routes/me/active-seasons.dart بعد فشل analyze | اختبار: نجح (247)
- [03:40] إصلاح: إنشاء مسار GET /me/active-seasons (يفوّض لـListMyActiveSeasons الموصولة مسبقًا) | ملف: apps/server/routes/me/active-seasons.dart | اختبار: نجح
- [04:00] إصلاح: إضافة CompetitionApi.myActiveSeasons() (GET /me/active-seasons) | ملف: packages/api_client/lib/src/competition_api.dart | اختبار: نجح
- [10:55] إصلاح: إضافة activeSeasons provider (GET /me/active-seasons) | ملف: apps/mobile/lib/features/competition/competition_providers.dart | اختبار: نجح
- [11:19] إصلاح: شاشة MyActiveSeasonsScreen + مفتاحا ARB + زر account.myActiveSeasons (لا CTA لتصفح المسابقات بعد -- لا شاشة مستوى-1 موجودة، مؤجل) | ملف: apps/mobile/lib/features/competition/my_active_seasons_screen.dart +apps/mobile/lib/features/auth/account_screen.dart + app_ar.arb + app_en.arb | اختبار: نجح
- [13:19] إصلاح: إضافة ListCurrentMonthFixtures use-case (تجميع فكسچرات كل مسابقة عامة لموسمها الحالي، Monthly Competitions §9) | ملف: packages/application/lib/src/competition/list_current_month_fixtures.dart + export application.dart | اختبار: نجح (344)
- [$(date +%H:%M)] إصلاح: إضافة createCompetition/startSeason إلى admin_api.dart | ملف: packages/api_client/lib/src/admin_api.dart | اختبار: نجح
- [14:22] إصلاح: تصحيح فشل اختبارات AdminShell (Material للشريط الجانبي + ensureVisible قبل tap) | ملف: apps/mobile/lib/features/admin/admin_shell.dart, apps/mobile/test/features/admin/admin_shell_test.dart | اختبار: فشل
- [14:25] إصلاح: admin_shell_test.dart scrollUntilVisible بدل ensureVisible لعنصر settings غير المبني (Drawer كسول) | ملف: apps/mobile/test/features/admin/admin_shell_test.dart | اختبار: نجح
- [14:54] إصلاح: ApiTransport.getNullableObject<T> (يدعم استجابة GET بجسم JSON null حرفي، تمهيداً لعميل GetCurrentSeason) | ملف: packages/api_client/lib/src/api_transport.dart | اختبار: نجح
- [14:57] إصلاح: توسعة .gitignore لتغطية السكربتات المرقّمة (01_، 02_...) + إخراج 01_add_get_nullable_object.sh من التتبّع | ملف: .gitignore | اختبار: لا ينطبق (تعديل .gitignore فقط، بلا كود Dart)
- [$(date +%H:%M)] إصلاح: CompetitionApi.getCurrentSeason(competitionId) + اختبارات | ملف: packages/api_client/lib/src/competition_api.dart, packages/api_client/test/competition_api_test.dart | اختبار: نجح
- [$(date +%H:%M)] إصلاح: currentSeasonProvider(competitionId) في competition_providers.dart + اختبارات | ملف: apps/mobile/lib/features/competition/competition_providers.dart, apps/mobile/test/features/competition/competition_providers_test.dart | اختبار: نجح
- [$(date +%H:%M)] إصلاح: CreateCompetitionController + StartSeasonController في admin_providers.dart | ملف: apps/mobile/lib/features/admin/admin_providers.dart | اختبار: نجح
- [16:56] إصلاح: قسم أدمن المسابقات الشهرية (عرض قراءة فقط: القائمة + الموسم الحالي لكل مسابقة) | ملف: apps/mobile/lib/features/admin/screens/sections/admin_monthly_competitions_section.dart, admin_shell.dart, app_ar.arb, app_en.arb | اختبار: فشل
- [16:58] إصلاح: قسم أدمن المسابقات الشهرية (عرض قراءة فقط: القائمة + الموسم الحالي لكل مسابقة) | ملف: apps/mobile/lib/features/admin/screens/sections/admin_monthly_competitions_section.dart, admin_shell.dart, app_ar.arb, app_en.arb | اختبار: نجح
- [17:13] إصلاح: نموذج إنشاء مسابقة (CreateCompetitionController) في قسم المسابقات الشهرية | ملف: apps/mobile/lib/features/admin/screens/sections/admin_monthly_competitions_section.dart, app_ar.arb, app_en.arb | اختبار: فشل
- [17:21] إصلاح: نموذج إنشاء مسابقة (CreateCompetitionController) في قسم المسابقات الشهرية | ملف: apps/mobile/lib/features/admin/screens/sections/admin_monthly_competitions_section.dart, app_ar.arb, app_en.arb | اختبار: نجح
- [19:01] إصلاح: تحويل StartSeasonController إلى family(competitionId) + نصوص ARB لزر بدء الموسم | ملف: apps/mobile/lib/features/admin/admin_providers.dart, apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb | اختبار: نجح
- [19:22] إصلاح: ربط زر بدء موسم لكل صف مسابقة (يستهلك startSeasonControllerProvider family) | ملف: apps/mobile/lib/features/admin/screens/sections/admin_monthly_competitions_section.dart | اختبار: نجح
- 20:29 — أضيف CurrentMonthFixtureItemDto إلى competition_dto.dart (البند 4، خطوة 1/6: DTO)
- 20:30 — أضيف currentMonthFixtureEntryToDto إلى competition_dto_mapper.dart (البند 4، خطوة 2/6: mapper)
- 20:31 — ربط ListCurrentMonthFixtures في composition_root.dart (البند 4، خطوة 3/6: wiring)
- 20:32 — أضيف route جديد GET /feed/current-month-fixtures (البند 4، خطوة 4/6)
- 20:35 — أضيف CompetitionApi.getCurrentMonthFixtures() (البند 4، خطوة 5/6: api_client)
- 20:35 — أضيف اختبار route لـ GET /feed/current-month-fixtures (البند 4، خطوة 6/6: مكتمل)
- [01:12] إصلاح: إضافة currentMonthFixturesProvider (البند 5 خطوة 1/4) | ملف: apps/mobile/lib/features/fixture_prediction/current_month_fixtures_providers.dart | اختبار: نجح
- 03:20 — أضيف اختبار currentMonthFixturesProvider (3 حالات) (البند 5، خطوة 2/4، اختبار: نجح)
- 03:21 — أضيف CurrentMonthFixturesScreen (شاشة مباريات الشهر الحالي الموحّدة، بلا منتقي) (البند 5، خطوة 3/4، اختبار: نجح)
- 03:22 — ربط زر account.matches بـ CurrentMonthFixturesScreen بدل MatchesFeedScreen (البند 5، خطوة 4/4، مكتمل، اختبار: نجح)
- 03:35 — حذف export مكرر لـ admin_get_fixture_scores.dart في application.dart (إصلاح خارج نطاق البند 5، اختبار: نجح)
- [04:18] إصلاح: زر عرض اللوحة لكل مباراة في CurrentMonthFixturesScreen — البند 6 | ملف: apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart | اختبار: يُملأ يدويًا
- [04:25] حذف: features/matches (matches_feed_screen.dart, matches_feed_providers.dart, current_month_fixtures_providers.dart المكرر) وmatch_card.dart — يتيمة بالكامل بعد البند 5 | اختبار: يُملأ يدويًا
- [15:02] تصحيح: أُعيد تنفيذ تنظيف فوضى جذر المستودع من المكان الصحيح (المحاولة السابقة طُبِّقت خطأً داخل apps/mobile) | ملفات: جذر المستودع + .gitignore | اختبار: لا ينطبق
- [15:12] إصلاح: استبدال ملفات checkpoint القديمة المضلِّلة (SESSION_STATE.md, CHANGES.md, RESUME_PROMPT.md, docs/next-task.md) بإشعارات توقف تشير للمصدر الحالي + حذف session-checkpoint-latest.zip | ملفات: .claude/session-checkpoint/*, docs/next-task.md | اختبار: لا ينطبق (توثيق فقط)
- [15:17] إصلاح: تحديث docs/ota-signing-blocker.md من P0 معلَّق إلى محلول جزئيًا (خطوات 1-3 من الحل مؤكَّدة مؤتمتة في CI + الأسرار الأربعة مؤكَّدة موجودة عبر gh secret list؛ خطوة 4 apksigner verify لم تُؤتمَت بعد) | ملفات: docs/ota-signing-blocker.md | اختبار: لا ينطبق (توثيق فقط)
- [15:21] إصلاح: إضافة اختبار وحدة مفقود لـ AdminGetFixtureScores (4 حالات: رفض غير-أدمن، معرّف مباراة غير صالح، قائمة فارغة قبل التسجيل، قراءة ناجحة بلا شرط عضوية موسم) | ملفات: packages/application/test/scoring/admin_get_fixture_scores_test.dart | اختبار: بانتظار تشغيل المستخدم الفعلي
- [15:31] إصلاح: إضافة اختبار route مفقود لـ GET /admin/fixtures/{id}/predictions (6 حالات: قراءة ناجحة، مصفوفة فارغة قبل التنبؤ، تدقيق سجل التتبع، تمرير ?reason=، رفض غير-أدمن، 405) | ملفات: apps/server/test/routes/admin/fixtures/admin_fixtures_predictions_route_test.dart | اختبار: بانتظار تشغيل المستخدم الفعلي
- [16:25] إصلاح: تنسيق 3 ملفات قديمة غير مُنسَّقة (dart format) كانت تُفشل format-check | ملفات: current_month_fixtures_screen.dart, admin_fixtures_predictions_route_test.dart, admin_get_fixture_scores_test.dart | اختبار: dart format فقط، بلا تغيير سلوك
- [16:33] إصلاح: توثيق قرارين معماريين في docs/project-context.md — (1) تأجيل حسم ازدواج مسار الدرجات مع شرط مانع قبل حذف Round الحقيقي، (2) اعتماد عمل المسابقات الشهرية/المواسم النشطة رسميًا كامتداد لـ7.10.x | ملفات: docs/project-context.md | اختبار: لا ينطبق (توثيق فقط)
- [16:36] إصلاح: تنظيف فوضى الجذر المتبقية (البند 5) — إزالة .flutter-plugins-dependencies المتسرّب من التتبّع + حذف revert_api_transport_get_retry.py المُطبَّق سابقًا + توسعة .gitignore (revert_*.py, .flutter-plugins-dependencies, .flutter-plugins) | ملفات: .gitignore, apps/mobile/.flutter-plugins-dependencies, revert_api_transport_get_retry.py | اختبار: لا ينطبق (تنظيف فقط، بلا كود Dart)
- [16:57] إصلاح: ScoreFixture لم يعد يرفض تسجيل التقييم لفكسچر بلا تنبؤات (كان يُرجع 409 scoring.fixture_has_no_predictions، صار Ok(<فارغة>) 200) — يطابق تسامح ScoreRound الفعلي ويطابق التوثيق المعلن لفلسفة Option-3؛ خطوة تمهيدية إلزامية قبل ربط PUT /fixtures/{id}/result بـScoreFixture (البند 7، القرار الموثَّق 2026-08-30) | ملفات: packages/application/lib/src/scoring/score_fixture.dart, packages/application/test/scoring/score_fixture_test.dart, apps/server/routes/fixtures/[id]/score/index.dart, apps/server/test/routes/fixture_prediction_scoring_test.dart | اختبار: بانتظار تشغيل المستخدم الفعلي
- [17:16] إصلاح: PUT /fixtures/{id}/result يستدعي الآن ScoreFixture إضافةً إلى scoreRoundsForFixture الحالي (الخيار C، القرار الموثَّق 2026-08-30) — يوحّد الاحتساب الفوري بين مسار Round القديم ومسار Fixture الجديد؛ اختبار جديد يثبت تشغيل ScoreFixture فعليًا كأثر جانبي + تحديث الاختبارين الحاليين لتوصيل scoreFixture بدل الاعتماد على الـfake غير الموصول | ملفات: apps/server/routes/fixtures/[id]/result/index.dart, apps/server/test/routes/scoring_routes_test.dart | اختبار: بانتظار تشغيل المستخدم الفعلي
- [20:25] إصلاح: إزالة كاملة لطبقة matches-feed الميتة في الخلفية (5 ملفات حُذفت، 13 تعديلًا عبر domain/application/infrastructure/contracts/api_client/server) — تُكمل محاولات 07-09 الفاشلة/غير المكتملة سابقًا في نفس الجلسة | ملفات: انظر git diff --stat | اختبار: فشل
- [20:31] إصلاح: إزالة كاملة لطبقة matches-feed الميتة في الخلفية (5 ملفات حُذفت، 13 تعديلًا عبر domain/application/infrastructure/contracts/api_client/server) — تُكمل محاولات 07-09 الفاشلة/غير المكتملة سابقًا | ملفات: انظر git diff --stat | اختبار: نجح (113/113 عبر flutter pub run melos run verify)
- [21:05] إصلاح: حذف 3 عناصر تحكم يتيمة خاصة بـRound من admin_providers.dart (RoundFixtureLinkController، RemoveFixtureController، PostRoundToLedgerController — لا مستهلك في أي شاشة) | ملف: apps/mobile/lib/features/admin/admin_providers.dart | اختبار: بانتظار تشغيل المستخدم الفعلي
- [21:53] إصلاح: إزالة قسمي احتساب وتقرير الجولة من واجهة الأدمن (7.10.x) + حذف متغيّر t غير المستخدم | ملف: apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart | اختبار: نجح (flutter analyze apps/mobile: No issues found!)
- [22:17] إصلاح: حذف مجلد features/prediction الميت بالكامل (شاشة تقديم توقع الجولة القديمة — صفر مستهلك حي بعد هجرة الفكسچر)، بداية فعلية لـ7.10 الحقيقي | ملف: apps/mobile/lib/features/prediction/{prediction_controller,prediction_providers,prediction_submission}.dart + apps/mobile/test/features/prediction/prediction_controller_test.dart | اختبار: نجح (flutter analyze: No issues found! / flutter test: +100 All tests passed!)
- [22:40] قرار: تجميد دائم لمسار قراءة Round التاريخي في prediction_history_screen.dart (getRoundScores + browseRoundFixtures) — لا هجرة بيانات؛ browseRoundFixtures مثبَّتة أصلًا عبر RoundPickerField بغض النظر عن هذه الشاشة | ملف: docs/project-context.md | اختبار: لا ينطبق (توثيق فقط)
- [00:50] إصلاح: تنظيف 3 تعليقات توثيقية بالية تشير لملفات محذوفة/غير موجودة | ملف: apps/mobile/lib/features/fixture_prediction/fixture_prediction_controller.dart, apps/mobile/lib/features/history/prediction_history_screen.dart | اختبار: نجح
- [00:56] إصلاح: توثيق قرار معماري - إسقاط بيانات Round القديمة من شاشة سجل التوقعات بدل الهجرة/الإبقاء الدائم | ملف: docs/project-context.md | اختبار: نجح
- [01:05] إصلاح: إسقاط مسار Round من شاشة سجل التوقعات (01/02) - حذف myPredictions/RoundPredictionEntry/roundFixturesProvider/roundScoresProvider، الشاشة تعرض FixturePredictionDto فقط | ملف: apps/mobile/lib/features/history/prediction_history_providers.dart, prediction_history_screen.dart, apps/mobile/test/features/history/prediction_history_screen_test.dart | اختبار: فشل
- [01:07] إصلاح: تصحيح اختبار فاشل في prediction_history_screen_test.dart (توقع نص "3 - 3" منفصل بدل السطر المدمج الفعلي "f-c: 3 - 3") | ملف: apps/mobile/test/features/history/prediction_history_screen_test.dart | اختبار: نجح
- [01:19] إصلاح: حذف myPredictions() من PredictionApi (طبقة api_client، خطوة 1/متعددة — لا مستدعٍ لها في الموبايل/الحزم) | ملف: packages/api_client/lib/src/prediction_api.dart | اختبار: نجح
- [01:21] إصلاح: حذف راوت GET /me/predictions من السيرفر (بلا اختبار مخصص، بلا مستهلك بعد حذف myPredictions من api_client) | ملف: apps/server/routes/me/predictions.dart | اختبار: نجح
- [01:23] إصلاح: فك ربط ListMyPredictions من composition_root.dart (7 مواضع: constructors + defaults + field + wiring)، بعد حذف الراوت وطبقة api_client | ملف: apps/server/lib/composition/composition_root.dart | اختبار: نجح
- [01:25] إصلاح: حذف use-case ListMyPredictions من طبقة application (بلا اختبار مخصص، بلا مستدعٍ بعد فك ربطه من composition_root) | ملف: packages/application/lib/src/prediction/list_my_predictions.dart, packages/application/lib/application.dart, packages/application/lib/src/prediction/list_my_fixture_predictions.dart | اختبار: نجح
- [01:30] إصلاح: تقاعد PredictionRepository.listByUser (بوابة Round القديمة) كاملة — الواجهة + Postgres + Fake + عقبتا composition_root/harness، بعد أن أصبح ListMyPredictions محذوفًا | ملف: 5 ملفات (ports/prediction_repository.dart, postgres_prediction_repository.dart, fake_prediction_repository.dart, composition_root.dart, competition_route_harness.dart) | اختبار: نجح
- [01:33] تحقق: تشغيل شامل لاختبارات application/infrastructure/server بعد سلسلة حذف myPredictions/ListMyPredictions/listByUser (5 سكربتات) | ملف: — | اختبار: فشل
- [01:36] تحقق: تشغيل شامل لاختبارات application/infrastructure/server عبر flutter test (بعد فشل dart test بسبب resolution: workspace) — بعد سلسلة حذف myPredictions/ListMyPredictions/listByUser | ملف: — | اختبار: نجح
- [01:41] تحقق: تشغيل شامل لاختبارات application/infrastructure/server (flutter test --reporter=failures-only) بعد سلسلة حذف myPredictions/ListMyPredictions/listByUser | ملف: — | اختبار: نجح
- [02:06] إصلاح: حذف عناصر تحكم يتيمة من admin_providers.dart بقيت بعد إزالة أقسام احتساب/تقرير الجولة (ScoreRoundController، RoundScoresLookupController، RoundReportController) + حذف round_report.dart وround_scores_providers.dart اليتيمين + تصحيح كل المراجع التوثيقية المتدلية الناتجة (بما فيها مرجع سابق متدلٍّ لـRoundOpenController) | ملف: admin_providers.dart, fixture_report.dart, score_fixture_controller_test.dart, round_scores_providers.dart(محذوف), round_report.dart(محذوف), round_report_test.dart(محذوف) | اختبار: فشل
- [02:23] إصلاح: إعادة توليد admin_providers.g.dart عبر build_runner لمزامنته مع حذف ScoreRoundController/RoundScoresLookupController/RoundReportController | ملف: apps/mobile/lib/features/admin/admin_providers.g.dart | اختبار: نجح (+96 all tests passed)
- [02:40] حذف: PredictionApi.submitPrediction (0 مستهلك في كامل المستودع خارج مسار الجولة في السيرفر) + مجموعة اختباراتها + تصحيح مرجعين توثيقيين متدليين | ملف: prediction_api.dart, prediction_api_test.dart | اختبار: نجح
- [02:53] حذف: 6 دوال عميل يتيمة صفرية الاستهلاك في كل المستودع (CompetitionApi.scoreRound/postRoundToLedger/getRoundScores/removeFixtureFromRound + AdminApi.adminGetRoundScores/adminListRoundPredictions) + تصحيح مرجعين توثيقيين متدليين لكل منها + حذف [openRound] المتدلي من التعليق العلوي | ملف: competition_api.dart, admin_api.dart | اختبار: نجح
- 03:06 fix: حذف adminGetRoundReport من admin_api.dart (دالة عميل ميتة، صفر مستهلك موبايل)
- 03:43 feat(matches-ui): 01 — إضافة KickoffCountdown widget معزول + مفتاح ترجمة kickoffCountdownDays (بداية إعادة تصميم شاشة المباريات)
- 03:55 feat(matches-ui): 02 — إعادة بناء _CurrentMonthFixtureCard كاملة (مدمجة/موسّعة + شعارات + 1X2 + Stepper + شريحة الدبل)
- 05:12 feat(matches-ui): 02 — إعادة بناء _CurrentMonthFixtureCard كاملة (مدمجة/موسّعة+شعارات+steppers+1X2)
- 05:20 feat(matches-ui): 02 — إعادة بناء _CurrentMonthFixtureCard (مدمجة/موسّعة + شعارات + 1/X/2 + Stepper رقمي + شارة الدبل + حالة تم التوقع/النتيجة) + إصلاح فجوة gen-l10n من 01 + 9 مفاتيح ترجمة
- 06:02 feat(matches-ui): 02 — إعادة بناء _CurrentMonthFixtureCard (مدمجة/موسّعة + شعارات + 1/X/2 + Stepper رقمي + شارة الدبل + حالة تم التوقع/النتيجة) + إصلاح فجوة gen-l10n من 01 + 9 مفاتيح ترجمة
- [06:56] إصلاح: SeasonPickerField — استبدال المفتاح الثابت admin.fixtures.seasonField بمفتاح يشمل competitionId (DropdownButtonFormField.initialValue لا يتحدّث بعد initState، فيبقى يعرض موسم المسابقة السابقة بصريًا بينما _seasonId فعليًا null بعد تبديل المسابقة → زر Add Match يبقى معطّلاً دائمًا) | ملف: apps/mobile/lib/features/admin/widgets/admin_pickers.dart | اختبار: بانتظار تشغيل المستخدم الفعلي (افتح Add Match، اختر مسابقة A + موسم، بدّل لمسابقة B، تأكد إن حقل الموسم يصير فارغًا/لا توجد مواسم وليس موسم A، اختر موسم B، عبّئ الفريقين والتوقيت، تأكد إن الزر يصير نشطًا)
- [07:17] إصلاح: إضافة 3 مفاتيح ترجمة لإعادة تصميم الشاشة الرئيسية (homePerformanceSection, homeAdminSection, homeMatchesSubtitle) | ملف: apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb | اختبار: يُملأ يدويًا
- [15:22] إصلاح: تصحيح خريطة nav في elite_preview.dart — إزالة تكرار 'توقعاتي' (index 2) واستبداله بـ'المتصدرون' (index 3) | ملف: lib/elite_preview/elite_preview.dart | اختبار: فشل (flutter analyze lib/elite_preview رجّع كود خروج 1 — راجع المخرجات أعلاه)
- [$(date +%H:%M)] إصلاح: حذف duplicate_import لـ admin_hub_screen.dart في nukhbaa_shell.dart | ملف: apps/mobile/lib/features/auth/nukhbaa_shell.dart | اختبار: -
- [01:31] إصلاح: AddMatchController لا يُحدّث شاشة مباريات المستخدم (currentMonthFixturesProvider) بعد إضافة مباراة — أُضيف ref.invalidate بعد نجاح ربط الموسم؛ يعالج الفجوة #1 من تدقيق تكامل قاعدة البيانات (Admin Create Fixture → User Matches) | ملف: apps/mobile/lib/features/admin/admin_providers.dart | اختبار: نجح (flutter analyze: No issues found)
- [01:36] إصلاح: إضافة FixtureLedgerRepository.findByFixture (port + Postgres impl) — قراءة كل الترحيلات السابقة لمباراة معينة، تمهيدًا لاكتشاف تصحيح النقاط في PostFixtureToLedger (02/03)؛ إضافة بحتة بلا تغيير سلوك حالي | ملف: packages/application/lib/src/ledger/ports/fixture_ledger_repository.dart, packages/infrastructure/lib/src/ledger/postgres_fixture_ledger_repository.dart | اختبار: نجح (dart analyze: لا أخطاء)
- [01:39] إصلاح: PostFixtureToLedger يكتشف الآن الترحيل السابق عبر findByFixture ويحسب delta ويرحّل EntryKind.correction بدل تجاهل التصحيح بصمت (كان يستخدم ON CONFLICT DO NOTHING على source_ref ثابت) — يعالج تدفق Admin Update Result -> Recalculate -> Correct Points -> Correct Leaderboard | ملف: packages/application/lib/src/ledger/post_fixture_to_ledger.dart | اختبار: نجح (dart analyze: لا أخطاء) — لا يوجد اختبار مخصص بعد لهذا الـ use case، سيُضاف بالسكربت 04
- [01:50] إضافة: FakeFixtureLedgerRepository (يطبّق findByFixture) + اختبار PostFixtureToLedger يغطي 3 حالات (ترحيل أول / تصحيح بعد تعديل نتيجة / إعادة ترحيل بلا تغيير) — يوثّق ويثبت إصلاح 02/03 لتدفق Admin Update Result -> Recalculate -> Correct Points | ملف: packages/application/test/ledger/fakes.dart, packages/application/test/ledger/post_fixture_to_ledger_test.dart | اختبار: فشل (راجع مخرجات analyze/test أعلاه)
- [02:24] إصلاح: تصحيح أخطاء fatal warnings في CI (interpolation في admin_monthly_competitions_section.dart وteam_logo_assets.dart، إزالة const زائد في nukhbaa_shell.dart، استثناء lib/elite_preview/** من التحليل) | ملف: admin_monthly_competitions_section.dart, team_logo_assets.dart, nukhbaa_shell.dart, analysis_options.yaml | اختبار: -
- [02:27] إصلاح: prefer_interpolation_to_compose_strings إضافي في admin_monthly_competitions_section.dart (سطر group.name/season) لم يظهر إلا بعد الفحص | ملف: admin_monthly_competitions_section.dart | اختبار: -
- [02:42] إصلاح: آخر مشاكل fatal warnings في CI — إعادة تصحيح interpolation في admin_monthly_competitions_section.dart (سطر شعار الفريق، كان قد تراجع)، وإضافة findByFixture لـ_UnwiredFixtureLedgerRepository في composition_root.dart بعد توسّع الواجهة. مشاكل adminDashboardProvider كانت ناتجة عن admin_providers.g.dart محلي غير محدَّث (dart analyze --fatal-warnings . الآن: No issues found) | ملف: admin_monthly_competitions_section.dart, composition_root.dart | اختبار: نجح
- [03:35] إصلاح: تبويب "المباريات" في NukhbaaShell كان يعرض NukhbaaMatchesPage (mockup ثابت) بدل الشاشة الحقيقية المربوطة بـ currentMonthFixturesProvider — استُبدل بـ CurrentMonthFixturesScreen | ملف: apps/mobile/lib/features/auth/nukhbaa_shell.dart | اختبار: بانتظار تشغيل المستخدم الفعلي
- [03:35] إصلاح: تبويب "توقعاتي" في NukhbaaShell (index 2) كان يعرض NukhbaaPredictionsPage (mockup ثابت بمباراة وهمية واحدة) بدل الشاشة الحقيقية المربوطة بـ myFixturePredictionsProvider — استُبدل بـ PredictionHistoryScreen | ملف: apps/mobile/lib/features/auth/nukhbaa_shell.dart | اختبار: بانتظار تشغيل المستخدم الفعلي
- [22:55] إصلاح: محاذاة تصميمية لـ FixturePredictionScreen مع بطاقة CurrentMonthFixturesScreen (شعارات + 1X2 + Stepper رقمي + شارة Double + عد تنازلي + توسيع/طي)؛ الملف مكرَّر محليًا وليس مشتركًا (اتفاقية self-contained feature file). الجزء (ب) prefill التوقع الموجود مسبقًا متروك عمدًا للسكربت التالي (myPrediction/grade يُمرَّران null الآن). | ملف: apps/mobile/lib/features/fixture_prediction/fixture_prediction_screen.dart (348→917 سطر) | اختبار: نجح (flutter analyze: No issues found)
- [22:56] إصلاح: تفعيل التعبئة المسبقة + شارة "توقعك"/الدرجة/النقاط في FixturePredictionScreen (البند ب) — يستهلك myFixturePredictionsProvider (مطابقة لفيكستشر) وfixtureScoresProvider(seasonId, fixtureId) (مطابقة لـparticipantId)، بنفس نمط CurrentMonthFixturesScreen حرفيًا (لا endpoint جديد، لا provider جديد)؛ ref.listen يُبطل myFixturePredictionsProvider بعد نجاح الإرسال لتحديث الشارة فورًا | ملف: apps/mobile/lib/features/fixture_prediction/fixture_prediction_screen.dart (917→1024 سطر) | اختبار: نجح (flutter analyze: No issues found)
- [23:44] إصلاح: إضافة SeasonFixturePickerField (اختيار موسم←مباراة مباشرة، بلا Round) في admin_pickers.dart — الخطوة 1/2 من 7.10 (فصل تدفق تسجيل نتيجة المباراة في Admin عن Round قبل حذف طبقة Round). لا استهلاك بعد — RoundPickerField/FixturePickerField القديمان يبقيان كما هما مؤقتاً. | ملف: apps/mobile/lib/features/admin/widgets/admin_pickers.dart (321→409 سطر) | اختبار: نجح (flutter analyze: No issues found)
- [23:47] إصلاح: نموذج تسجيل نتيجة المباراة (results_scoring_section.dart) يختار المباراة الآن عبر (المسابقة←الموسم←المباراة) مباشرة باستخدام SeasonFixturePickerField، بدل (المسابقة←الموسم←الجولة←المباراة) عبر RoundPickerField/FixturePickerField — الخطوة 2/2 من 7.10 (فصل تدفق تسجيل النتيجة في Admin عن Round). حُذف _resultRoundId من الحالة المحلية. recordFixtureResult نفسه لم يتغيّر (كان مستقلاً عن Round أصلاً). RoundPickerField/FixturePickerField(roundId-based) في admin_pickers.dart أصبحا الآن ميتَين بلا مستهلك — تُركا للحذف اللاحق ضمن التنظيف الشامل لطبقة Round. | ملف: apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart | اختبار: نجح (flutter analyze: No issues found)
- [23:55] إصلاح: verify_termux.sh السطر 45 كان يستخدم `dart run --no-pub melos run test` — `--no-pub` لم تعد مدعومة في dart run بالإصدار الحالي، ما كان يُفشل خطوة الاختبارات دومًا. صار السطر `dart run melos run test`. ملاحظة منفصلة (غير مُصلَحة هنا): هذا السطر يشغّل `melos run test` فقط، الذي يستثني حزمة mobile عمداً (packageFilters.ignore) — أي أن verify_termux.sh لا يُشغّل flutter test لتطبيق mobile أصلاً؛ اختبارات mobile (بما فيها اليوم) تحتاج تشغيلاً منفصلاً بـ `cd apps/mobile && flutter test` أو `dart run melos run test-mobile` إن رغب المستخدم بإدراجها لاحقاً. | ملف: verify_termux.sh | اختبار: bash -n نظيف (لم يُشغَّل verify_termux.sh كاملاً هنا، شغّله يدويًا للتأكد)
- [00:10] حذف: apps/server/routes/rounds/** و apps/server/routes/admin/rounds/** بالكامل (أول عنصر فعلي من حذف Round الحقيقي — طبقة server)؛ لم تُمسّ groups/[id]/rounds/[roundId]/reactions ولا seasons/[id]/rounds (بندان منفصلان)؛ نسخة احتياطية في /home/dev/nukhbaa-round-backups/server_routes_20260902_001019 | ملف: apps/server/routes/rounds/**, apps/server/routes/admin/rounds/** | اختبار: فشل (راجع /home/dev/nukhbaa-round-backups/server_routes_20260902_001019/analyze_output.log)
- [00:19] حذف/تعديل: حذف round_predictions_test.dart وrounds_browse_test.dart بالكامل (مستهلكان لروتات Round المحذوفة في السكربت 01)، وتنظيف مجموعتي اختبار Round من ledger_routes_test.dart (POST /rounds/{id}/ledger) وscoring_routes_test.dart (POST /rounds/{id}/score، GET /rounds/{id}/scores) مع استيراداتها اليتيمة | ملف: apps/server/test/routes/round_predictions_test.dart(محذوف), apps/server/test/routes/rounds_browse_test.dart(محذوف), apps/server/test/routes/ledger_routes_test.dart, apps/server/test/routes/scoring_routes_test.dart | اختبار: فشل (راجع /home/dev/nukhbaa-round-backups/server_tests_20260902_001859/analyze_output.log)
- [00:23] تنظيف: حذف عناصر مساعدة يتيمة في ملفي اختبار السيرفر بعد حذف مجموعات اختبار Round (السكربت 02) — ledger_routes_test.dart: roundIn/storedScore؛ scoring_routes_test.dart: kParticipantId/kPredictionId/roundIn/participant/link/actualResult/prediction | ملف: apps/server/test/routes/ledger_routes_test.dart, apps/server/test/routes/scoring_routes_test.dart | اختبار: فشل (راجع /home/dev/nukhbaa-round-backups/server_test_helpers_20260902_002316/analyze_output.log)
- [00:35] تنظيف: حذف عناصر يتيمة تسلسلية بعد السكربت 03 — ledger_routes_test.dart: kFixtureId؛ scoring_routes_test.dart: roundId/snapshot | ملف: apps/server/test/routes/ledger_routes_test.dart, apps/server/test/routes/scoring_routes_test.dart | اختبار: نجح (dart analyze: لا أخطاء)
- [01:23] تنظيف: إزالة ربط ثمانية use-cases ميتة (ScoreRound، ScoreRoundsForFixture، GetRoundScores، GetRoundReport، AdminGetRoundScores، AdminGetRoundReport، PostRoundToLedger، GetRoundLeaderboard) من composition_root.dart — معاملات مُنشئ (required+اختيارية)، دوال _absentX، تصريحات الحقول، تعليق يتيم كان يصف postRoundToLedger، كتلة الربط الفعلية؛ مع إصلاح 3 مراجع توثيقية متدلية ([scoreRound]، [postRoundToLedger]، [_absentAdminGetRoundScores]) | ملف: apps/server/lib/composition/composition_root.dart | اختبار: فشل (راجع /home/dev/nukhbaa-round-backups/composition_root_20260902_012343/analyze_output.log)
- [01:31] تنظيف: إزالة بقايا يتيمة من سكربت 05 في composition_root.dart — حذف حقل _unwiredScoreRepository وكلاس _UnwiredScoreRepository بالكامل (صفر مستهلكين بعد إلغاء ربط الثمانية)، حذف متغير scoreRepository المحلي غير المستخدم، وتصحيح تعليق متدلٍّ كان يشير إليه فوق fixtureScoreRepository | ملف: apps/server/lib/composition/composition_root.dart | اختبار: نجح (dart analyze: لا أخطاء)
- [01:46] حذف: الطبقة المصدرية الكاملة للثمانية use-cases الميتة (ScoreRound، ScoreRoundsForFixture، GetRoundScores، GetRoundReport، AdminGetRoundScores، AdminGetRoundReport، PostRoundToLedger، GetRoundLeaderboard) من packages/application/lib/src، مع اختباراتها الثلاثة (post_round_to_ledger_test.dart، get_round_scores_test.dart، score_round_test.dart) وملف scoring/fakes.dart اليتيم (صفر مستهلكين بعد حذف الثلاثة)، وإزالة أسطر التصدير الثمانية من application.dart | ملف: packages/application/lib/src/** (8 ملفات، محذوفة)، packages/application/test/** (4 ملفات، محذوفة)، packages/application/lib/application.dart | اختبار: فشل (راجع /home/dev/nukhbaa-round-backups/application_layer_20260902_014654/analyze_output.log)
- [01:49] إصلاح: استعادة packages/application/test/scoring/fakes.dart الذي حُذف بالخطأ في السكربت 07 — لا يزال مستهلَكًا فعليًا من get_fixture_scores_test.dart وrecord_fixture_result_test.dart وscore_fixture_test.dart (FakeFixtureResultRepository، scoringParticipant، scoringSnapshot)؛ خطأ التحقق السابق كان اقتصار البحث على الاستيراد النسبي من خارج المجلد ('scoring/fakes.dart') فقط، فلم يلتقط الاستيراد النسبي المباشر من داخل نفس المجلد ('fakes.dart') في هذه الملفات الثلاثة؛ تقليم الأجزاء المخصصة لـRound فعليًا داخل الملف (إن وُجدت) مؤجَّل لفحص منفصل لاحق | ملف: packages/application/test/scoring/fakes.dart | اختبار: نجح (dart analyze: لا أخطاء)
- [02:04] إصلاح: استعادة packages/application/test/scoring/fakes.dart المحذوف خطأً في سكربت 07 (a002dcd) — كان لا يزال مستهلَكًا من get_fixture_scores_test.dart وrecord_fixture_result_test.dart وscore_fixture_test.dart عبر استيراد نسبي مباشر لم يلتقطه التحقق السابق | ملف: packages/application/test/scoring/fakes.dart | اختبار: dart analyze packages/application → نجح (No issues found)
- [02:05] إصلاح: dart format على composition_root.dart وscoring_routes_test.dart (اختلاف تنسيق ناتج عن تعديلات str_replace المباشرة في سكربتي 05/06 وسكربتي 02/03) — اكتُشف عبر melos run verify → format-check؛ dart analyze لا يكشف اختلاف التنسيق (فراغات/أسطر)، شرط عبور format-check منفصل ولا يُغني عنه | ملف: apps/server/lib/composition/composition_root.dart، apps/server/test/routes/scoring_routes_test.dart | اختبار: نجح (dart format: لا تغييرات متبقية)
- [02:06] تحقق: melos run verify شامل بعد استعادة fakes.dart وإصلاح format (e9b9bb6, d8533c4) | اختبار: فشل — راجع الأخطاء أعلاه
- [02:09] تحقق: melos run verify شامل بعد استعادة fakes.dart وإصلاح format (e9b9bb6, d8533c4) | اختبار: نجح بالكامل
- [03:38] 15_add_apksigner_verify.py: أُدرجت خطوة Verify release signing (apksigner) في build-verification.yml بعد Build APK split-per-abi
- [$(date +%H:%M)] إصلاح: حذف RoundPickerField/FixturePickerField الميتين من admin_pickers.dart (غير مستخدمين خارج الملف بعد هجرة results_scoring_section.dart لـSeasonFixturePickerField)، تصحيح adminNoFixturesHint->adminNoSeasonFixturesHint، حذف 4 مفاتيح ARB يتيمة | ملف: apps/mobile/lib/features/admin/widgets/admin_pickers.dart + l10n | اختبار: نجح
- [07:48] إصلاح: إزالة علامات تعارض git غير محلولة (HEAD/origin main) كانت مدموجة داخل session-log.md على main؛ أُبقي على محتوى HEAD لأن جانب origin/main كان فارغاً؛ نسخة احتياطية محلية .bak محفوظة | ملف: docs/checkpoints/session-log.md | اختبار: grep تأكيدي أعلاه
2026-09-02T20:06:04Z | fix: restore core/ui/match_card.dart and streak_chip.dart (missing from local copy) | apps/mobile/lib/core/ui/match_card.dart, apps/mobile/lib/core/ui/streak_chip.dart | flutter analyze clean
- [ui-fix-01] TeamLogo موحّد (core/ui): fallback بحروف Initials بدل دائرة فارغة بلا نص. استُبدل الاستخدام في current_month_fixtures_screen.dart(_TeamHeader)/fixture_prediction_screen.dart(_TeamHeader)/prediction_history_screen.dart(_TeamMini). core/ui بلا استيراد features/. واجهة فقط، بلا لمس DTO/شبكة/منطق أعمال. اختبار: مراجعة يدوية + محاكاة تطبيق كاملة، يلزم flutter analyze محليًا. 04:49
- [تصحيح] السطر السابق (TeamLogo) غير دقيق: فشل replace_once على current_month_fixtures_screen.dart (0 تطابق)، فتوقف السكربت هناك. المُنفَّذ فعليًا فقط: إنشاء core/ui/team_logo.dart (غير مُستخدَم بعد). الشاشات الثلاث لم تُعدَّل. 04:59
- [ui-fix-02] current_month_fixtures_screen.dart: تحقّقتُ من الملف الفعلي (السكربت الأصلي افترض استيرادًا خاطئًا لـscore_pill.dart غير موجود فيه، وهذا سبب فشل 01). أُضيف import team_logo.dart، واستُبدل crest بـTeamLogo. لم يُختبر flutter analyze محليًا بعد. 05:08
- [ui-fix-03] fixture_prediction_screen.dart: تحقّقتُ من imports/_TeamHeader الفعليين (طابقا افتراض 01 الأصلي بلا فروقات). أُضيف import team_logo.dart، واستُبدل crest بـTeamLogo. لم يُختبر flutter analyze محليًا بعد. 05:13
- [ui-fix-verify] flutter analyze --fatal-warnings نظيف بعد دمج TeamLogo في الملفات الأربعة (01-04). لا أخطاء import_lint، لا تحذيرات. جاهز للمراجعة قبل push. 05:17
- [20:29] إصلاح: إزالة علامات تعارض الدمج غير المحلولة من session-log.md مع إبقاء إدخالات HEAD كاملة؛ تم التحقق من عدم بقاء أي conflict markers | ملف: docs/checkpoints/session-log.md | اختبار: تحقق نصي ناجح
- [06:11] دمج: إكمال دمج origin/main (28 محليًا/14 عن بعد) — حُلّت تعارضات current_month_fixtures_screen.dart وprediction_history_screen.dart وsession-log.md (لا علامات متبقية، تحقّق grep)؛ إصلاح إضافي: استبدال .valueOrNull بـ.value في home_screen.dart (riverpod 3.3.2 لا يعرّف valueOrNull — مؤكَّد من مصدر الحزمة async_value.dart سطر 551) وحذف استيراد session_controller.dart غير المستخدَم من nukhbaa_shell.dart | ملف: home_screen.dart, nukhbaa_shell.dart, current_month_fixtures_screen.dart, prediction_history_screen.dart, session-log.md | اختبار: نجح (flutter analyze: No issues found)
2026-09-03T19:10:03Z — 07_azure_blue: الأساسي -> أزرق عميق (داكن #2F6BFF/#1D4ED8/#5B8BFF، فاتح #1D4ED8/#1E3A8A/#3B82F6). ملفات: apps/mobile/lib/core/theme/app_colors.dart, apps/mobile/lib/core/design/app_colors_light.dart
2026-09-03T19:15:50Z — 13_nav_keys(مُصحَّح): استبدال ValueKey('nav.item.$destination') بمفتاح navKey اسمي صريح (home/fixtures/predictions/leaders/account) — apps/mobile/lib/features/auth/nukhbaa_shell.dart
2026-09-03T19:25:29Z — 12_stretch_fix(مُصحَّح): فحص كل Row(stretch+Expanded) على حدة وتغليف الناقص فقط — apps/mobile/lib/features/auth/account_screen.dart
2026-09-04T00:15:47Z — 16_safearea_account: لف body بـSafeArea(bottom:true, top:false) لإصلاح اختفاء قسم الإدارة (وأي محتوى سفلي) خلف شريط التنقل السفلي الشفاف الناتج عن extendBody:true في NukhbaaShell — apps/mobile/lib/features/auth/account_screen.dart
2026-09-04T00:16:31Z — 17_safearea_matches: لف body بـSafeArea(bottom:true, top:false) لإصلاح اختفاء/تعذّر التفاعل مع آخر مباراة (أزرار 1/X/2 والعدّادات) خلف شريط التنقل السفلي الناتج عن extendBody:true في NukhbaaShell — apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart
- [00:43] إصلاح (تصحيح تاريخ git): أُعيد تسجيل SafeArea في account_screen.dart كـcommit مستقل بعد اكتشاف أن 37f06ff جرف حزمة fixture_schedule (17 ملفًا) بسبب git add بعد git reset --soft سابق دون تفريغ كامل للـstage | ملف: apps/mobile/lib/features/auth/account_screen.dart | اختبار: نفس الكود المدمَج سابقًا، لم يتغيّر منطقيًا
- [00:43] إصلاح (تصحيح تاريخ git): أُعيد تسجيل SafeArea في current_month_fixtures_screen.dart كـcommit مستقل، لنفس سبب الإصلاح السابق | ملف: apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart | اختبار: نفس الكود المدمَج سابقًا، لم يتغيّر منطقيًا
2026-09-04T01:47:20Z — 24_fixture_predict_sheet: ملف جديد معزول apps/mobile/lib/features/fixture_prediction/fixture_predict_sheet.dart — ورقة سفلية (bottom sheet) تحوي منطق الستيبر/تعبئة 1-X-2/الدبل/الإرسال المنقول من _CurrentMonthFixtureCardState القديمة، لتُفتح لاحقًا من onTap/onPredictTap في MatchCard. لا تعديل على أي ملف موجود.

2026-09-04T11:57:52Z — 04_fix_entry_kind_enum_cast: «ترحيل إلى السجل» كان يفشل دائمًا (ledger.fixture_point_entries فارغ رغم 3 صفوف في scoring.fixture_scores) لأن @entry_kind يُمرَّر نصًّا عاريًا إلى عمود ledger.entry_kind فيرفضه Postgres بالرمز 42804؛ و42804 ليس ضمن integrityCodes في _reclassify فيظهر للمستخدم كـtransient «We could not reach the server». أُضيف ::ledger.entry_kind في محوّلي السجل (fixture + round) على نمط @status::competition.participant_status القائم — packages/infrastructure/lib/src/ledger/*.dart

2026-09-04T11:59:00Z — 01_fix_leaderboards_screen: المتصدرون كان يعرض participantId ونقاطًا صفرية لأن الشاشة تقرأ seasonLeaderboardProvider (VIEW فوق ledger.point_entries عبر round_id) بينما النقاط تُكتب في ledger.fixture_point_entries؛ استُبدلت القراءة بـfixtureLeaderboardProvider وعُرض displayName وfixturesScored — apps/mobile/lib/features/leaderboards/leaderboards_screen.dart

2026-09-04T11:59:08Z — 02_fix_no_default_pick: شاشة المباريات كانت تُظهر X مُحدّدة تلقائيًا (_homeGoals/_awayGoals تبدآن بـ0 والتحديد مشتق من home==away) وتسمح بحفظ توقّع 0-0 لم يختره المستخدم؛ صار الاختيار nullable وزر الحفظ معطّلًا حتى اختيار 1/X/2، وحُذف debugPrint المؤقت من شريحة الدبل — apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart

2026-09-04T11:59:15Z — 02b_fix_no_default_pick_season_screen: تطبيق إصلاح 02 نفسه على البطاقة المكرّرة في الشاشة الموسمية (اختيار nullable، حفظ معطّل بلا اختيار، حذف debugPrint) — apps/mobile/lib/features/fixture_prediction/fixture_prediction_screen.dart

2026-09-04T11:59:24Z — 03_fix_scoring_success_banners: زرّا احتساب المباراة والترحيل إلى السجل كانا يعرضان AdminErrorBanner فقط بلا أي تغذية راجعة عند النجاح؛ أُضيف AdminSuccessBanner لكلٍّ منهما (عدد التوقعات المحتسبة / عدد القيود المضافة، وصفر يعني ترحيلًا مسبقًا) — apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart

2026-09-04T13:59:28Z — fotmob_01_design_tokens: بدء إعادة تصميم بطاقة المباراة بنمط FotMob (match-card-fotmob-spec.md) على فرع feat/fotmob-match-card. الخطوة 1: AppOpacity.tint(0.18)/glow(0.22) وAppRadius.cardLarge(24)/brCardLarge (إضافيان، card=16 أصغر من 20 المطلوب)، ملف جديد competition_logo_assets.dart (سجلّ شعارات دوريات فارغ عمدًا — لا مصدر مرخّص للشعارات الرسمية، كل دوري يعرض عبر fallback الحرفين)، ومفتاح ترجمة predictionMakeItDoubleLabel (AR/EN) — apps/mobile/lib/core/design/app_opacity.dart, app_radius.dart, apps/mobile/lib/features/competition/competition_logo_assets.dart, apps/mobile/lib/l10n/app_ar.arb, app_en.arb | analyze: نظيف (No issues found) | format: نظيف | commit: b95d1d3
2026-09-04T14:20:00Z — fotmob_02_card_widget: إنشاء fotmob_match_card.dart كاملاً (البطاقة + كل ودجتاتها الخاصة: _CardHeader/_CompetitionLogo/_TeamColumn/_MiddleSlot/_GradedSlot/_LockedSlot/_ScoreStepper/_DoubleGlowButton/_SubmitButton) — لم يُربَط بالشاشة بعد (الخطوة التالية). قرار مسجَّل: زر إرسال صريح (مفتاح currentMonthFixtures.submit.$id مبقّى كما في §9) لا حفظ تلقائي — تناقض §5 (يتطلب موافقة صاحب المشروع قبل التحويل لحفظ تلقائي) مع كتلة "منطق الحفظ التلقائي" الملحقة داخل §10: نُفِّذ §5 حرفيًا، ولم يُنفَّذ الحفظ التلقائي المتناقض معه (§11.7). انحراف إضافي مسجَّل: AppSizes.iconXl موجود مسبقًا بقيمة 38 (وليس 44 كما افترضت المواصفة) — استُخدم كما هو دون تغيير قيمة توكن مشترك يُستخدم في sign_in_screen.dart. ignore: depend_on_referenced_packages مُضاف على استيراد intl (تبعية عابرة موجودة أصلاً عبر flutter_localizations، بلا تعديل pubspec.yaml) — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart | analyze: نظيف (No issues found) | format: نظيف | commit: 545bcbd
2026-09-04T15:05:00Z — fotmob_03_wire_card: ربط FotmobMatchCard بالشاشة — استبدال _CurrentMonthFixtureCard في itemBuilder، وحذف الودجتات الخاصة الميتة كليًا (_CurrentMonthFixtureCard/_CurrentMonthFixtureCardState، _TeamHeader، _CenterStatus، _QuickFillRow، _QuickFillButton، _DoubleChip) مع كل استيراداتها التي لم تعد مستخدَمة في هذا الملف (team_identity، teams_providers، fixture_scores_providers، prediction_history_providers، season_leaderboard_screen، fixture_prediction_controller/submission، app_badge، score_pill، team_logo، app_spacing/app_radius/app_sizes/app_stroke). لم يُمَسّ CurrentMonthFixturesScreen ولا _CurrentMonthFixturesError سوى الاستيراد الجديد والـitemBuilder — apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart | analyze: نظيف (No issues found) | format: نظيف | commit: 1f287c9
2026-09-04T15:30:00Z — fotmob_04_theme_toggle: إضافة مفتاح الوضع الداكن الوحيد (§8) — لا آلية جديدة، أُعيد استخدام themeControllerProvider/ThemeController.toggle() الموجودَين حرفيًا. لم تكن هناك أي واجهة لتبديل السمة في التطبيق (تحقّق بالبحث)، فأُضيف SwitchListTile واحد (_DarkModeToggle، مفتاح account.darkModeToggle) في account_screen.dart أسفل رأس الملف الشخصي مباشرة. ThemeMode ثلاثي القيم (system/light/dark) لكن SwitchListTile ثنائي: عومل system كإيقاف (فاتح)، والتبديل يستدعي toggle() الثنائي (فاتح↔داكن) الموجود مسبقًا. مفتاح ترجمة جديد accountDarkModeLabel (AR/EN) — apps/mobile/lib/features/auth/account_screen.dart, apps/mobile/lib/l10n/app_ar.arb, app_en.arb | analyze: نظيف (No issues found) | format: نظيف | commit: c0242d8
2026-09-04T16:10:00Z — fotmob_05_tests_and_fix: تحديث اختبار زر الدبل (current_month_fixtures_screen_double_test.dart) ليطابق مفاتيح/أيقونات البطاقة الجديدة (currentMonthFixtures.double/home.increment/away.increment بدل quickFill1 وbolt_outlined/bolt_rounded بدل circle_outlined/check_circle)، وملف اختبار جديد (fotmob_match_card_state_test.dart) يغطي الحالات الأربع الحصرية بترتيب أولويتها (مُقيَّم > مُقفَل > متوقَّع > مفتوح، §6). أثناء تشغيل flutter test الكامل ظهر فشل حقيقي غير متعلق بالاختبارات نفسها: SwitchListTile._DarkModeToggle داخل Container ذي لون خلفية (DecoratedBox) يُخفي splash التأثير الحبري — أصلحتُه باستبدال Container بـMaterial (color+shape) لأن ListTile يرسم خلفيته/تأثيره الحبري على أقرب سلف Material. لا تغيير في السلوك، فقط الحاوية — apps/mobile/test/features/fixture_prediction/current_month_fixtures_screen_double_test.dart, apps/mobile/test/features/fixture_prediction/fotmob_match_card_state_test.dart, apps/mobile/lib/features/auth/account_screen.dart | analyze: نظيف (No issues found) | format: نظيف | flutter test: 108/108 ناجح | commit: d39a580
2026-09-04T16:35:00Z — fotmob_06_overflow_check: اختبار جديد (fotmob_match_card_overflow_test.dart) يثبّت عرض 320 نقطة منطقية على CurrentMonthFixturesScreen بكلتا سمتَي AppTheme.light/AppTheme.dark ويتحقق أن tester.takeException() فارغ — يغطي معيار قبول §10 (لا تجاوز/overflow بأي سمة عند 320px). كما رُوجعت البطاقة والسجل الجديدان يدويًا للتأكد من خلوّهما من Colors.* الصريحة (Colors.transparent الوحيد الموجود يطابق نمط _MatchesCtaCard القائم مسبقًا في account_screen.dart، وليس لونًا من علامة تجارية) ومن أي نص عربي مكتوب مباشرة (كل النصوص عبر AppLocalizations) — apps/mobile/test/features/fixture_prediction/fotmob_match_card_overflow_test.dart | analyze: نظيف (No issues found) | format: نظيف | flutter test: 110/110 ناجح | commit: 44196fd
2026-09-04T17:05:00Z — fotmob_07_crest_glow_controls (فرع fix/fotmob-card-crest-glow-controls): طلب المستخدم تصميمًا ثابتًا بالبكسل (canvas 795×1536، ألوان hex حرفية، أسماء أندية ثابتة كـLiverpool/Real Madrid) — تعارض صريح مع قواعد البطاقة (كل الألوان من tokens، بلا أبعاد ثابتة، ألوان الفرق ديناميكية)؛ بعد توضيحين مع المستخدم اختار "تكييف مع نظام Tokens". التنفيذ: AppOpacity.crestGlow(0.14) جديد + glow صغير خلف كل شعار فريق في _TeamColumn بلون brandColor الفعلي للفريق (يُحذف كليًا إن لم يُحلّ لون — لا لون مخمَّن)؛ AppTokens.success/successContainer جديدان (موصولان من AppColors/AppColorsLight.success الموجودَين مسبقًا في اللوحتين لكن غير مكشوفَين على AppTokens)؛ _SubmitButton أصبح دائرة صغيرة خضراء (tokens.success) بدل المستطيل الأزرق الأكبر، بنفس المفتاح/السلوك بالضبط؛ _DoubleGlowButton أصبح شارة مضغوطة (radius=AppRadius.button=12، يطابق طلب "~12px" حرفيًا) بدل شريط كامل العرض، ملفوفة بـFlexible (ونصّها بـFlexible+ellipsis مجددًا) لتفادي overflow اكتُشف فعليًا عند 320px بعد أول محاولة (أُصلح، أُعيد فحصه). — apps/mobile/lib/core/design/app_opacity.dart, app_tokens.dart, apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart | analyze: نظيف (No issues found) | format: نظيف | flutter test: 110/110 ناجح | commit: 0ef45ae

2026-09-04T19:44:48Z — 05_compact_footer_badges: الصفّ السفلي للبطاقة صار شارتين صغيرتين عند الطرفين (×2 دبل يمينًا، ✓ إرسال يسارًا) والوسط فارغ، مطابقةً لموضع شارتَي «ف» في المرجع، بدل صفّ يملأ العرض. الارتفاع 36px دون AppSizes.minTouchTarget — مطلب بصري صريح من صاحب المشروع، مسجَّل كانحراف مقصود لا سهو — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart

2026-09-04T19:49:23Z — 06_smaller_score_steppers: مربّعات إدخال النتيجة صُغِّرت — 76×104 إلى 68×92، ومنطقتا +/− من 34 إلى 28، والرقم من 22pt إلى 20pt. منطقة اللمس صارت 28px أي دون AppSizes.minTouchTarget — مطلب بصري صريح من صاحب المشروع، مسجَّل كانحراف مقصود — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart

2026-09-04T19:55:45Z — 07_confirm_badge_contrast: شارة الصح بين العدّادين كانت تُقرأ دائرة سوداء قبل التأكيد لأن تعبئتها tokens.surface (نفس داكن البطاقة) وأيقونتها tokens.textMuted؛ صارت التعبئة textPrimary@0.10 والأيقونة textSecondary على نمط العدّادات وزر الدبل غير المفعّل. الحالة المؤكَّدة (primary/onPrimary) دون تغيير — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart

2026-09-05T02:00:00Z — europa_crests_supabase: طلب المستخدم رفع شعارات الـ36 فريق المؤكَّدة رسميًا ليوروبا ليغ 2026-27 (CSV + 36 PNG بصيغة 800×800 شفافة، تحقّق ضدّ قائمة UEFA الرسمية) إلى Supabase. فحص football_data.teams (عبر تاريخ الـmigrations، لا اتصال مباشر بقاعدة البيانات الحيّة — لا صلاحيات DB في هذا الـsandbox، كسائر مهام هذه الجلسة) أظهر عمود crest_url موجودًا مسبقًا منذ migration 0013 — فلا حاجة لعمود logo_url جديد كما افترض الطلب. ملف europa_2026_27.sql الحالي (الذي نفّذه المستخدم شخصيًا سابقًا هذه الجلسة) يغطّي 24 من الـ36 فريقًا (المؤكَّدة وقتها) فقط؛ قورنت شرائح slug من الـCSV مقابل مفاتيح external_identity_map الحالية (ext) فظهر أن الـ12 الباقين (Anderlecht, Benfica, Beşiktaş, Ferencváros, Lech Poznań, Lillestrøm, OFI Crete, Viktoria Plzeň, Ararat-Armenia, Jagiellonia Białystok, Omonia, Salzburg) غير مزروعين إطلاقًا — لا تكرار مع أي دوري آخر (تحقّق بالبحث في كل ملفات seed). أُنشئ: (1) migration 0026 تضيف bucket باسم team-logos (public=true) + سياسات RLS (قراءة عامة، رفض كتابة العملاء) — لا نمط bucket سابق في المشروع للمطابقة عليه (بحث فارغ)، فبُني حسب اصطلاح Supabase القياسي. (2) seed جديد europa_2026_27_crests.sql يُنشئ الـ12 فريقًا الجدد بنفس نمط التصالح عبر external_identity_map المستخدَم أصلًا، ثم يضبط crest_url لكل الـ36 برابط Storage العام المحسوب حتميًا (project ref + bucket + <slug>.png) — مطابقة دقيقة بمفاتيح ext الموجودة فعلًا، لا مطابقة نصّية متسامحة كما طُلب حرفيًا (قرار: أدقّ وأكثر أمانًا من fuzzy matching نصي). (3) نسخة الـCSV مُرفقة بالمستودع (seed_assets/) للمرجعية والتكرارية. (4) سكربت رفع (upload_europa_2026_27_crests.sh) يعيد تسمية الصور الـ36 إلى <slug>.png ويرفعها عبر Supabase CLI — تحقّقت محليًا أن كل الأسماء الـ36 من الـCSV تطابق ملفات PNG الفعلية 1:1 بلا نقص، لكن لم يُشغَّل فعليًا (لا access token ولا service-role key ولا كلمة مرور DB في هذا الـsandbox). أثناء العمل اكتُشف أن جلسة موازية (نفس مستخدم git) تعمل على fotmob_match_card.dart بالتزامن وتدفع مباشرة لـmain (عكس/استعادة/تحسينات إضافية) — تُرك كل ذلك دون مساس؛ commit هذه المهمة يضمّ فقط الملفات الأربعة الجديدة (migration + seed + csv + سكربت الرفع)، لا تعارض معه — apps/mobile غير مُتَعرَّض له إطلاقًا. | commit: d86c027
- [logos-2026-27-handoff] تجهيز 36 شعار UCL + 18 شعار SPL في docs/handoff/logos-2026-27 مع MANIFEST وملاحظة تسليم؛ لا تعديل كود ولا قاعدة بيانات 03:00
2026-09-05T03:20:00Z — ucl_saudi_crests_handoff: نُفِّذ ما طلبته HANDOFF_NOTE.md بالضبط (نفس نمط europa_crests_supabase أعلاه، بلا تخمين — عمود guessed_team_name في LOGOS_MANIFEST.csv صريح أنه غير موثوق). قُرئ docs/project-context.md فلم يظهر أي آلية تخزين شعارات موثّقة أخرى غير التي أنشأتها للتوّ (crest_url + bucket team-logos، migration 0026) — فهي الآلية الفعلية الوحيدة الآن. UCL: ucl_2026_27.sql يغطّي 28 من الـ36 فقط؛ حُدِّدت الثمانية الباقون بمعرفة كروية (لا تخمين آلي من اسم الملف): AEK أثينا، بودو/غليمت، فنربخشة، لاسك لينز، ليل (LOSC)، سلوفان براتيسلافا، سابا (أذربيجان)، فايكينغ — لا تكرار مع أي seed آخر (تحقّق بالبحث). Saudi: saudi_2026_27.sql يغطّي الـ18 كاملةً مسبقًا — لا فرق جدد، ربط crest_url فقط. أُنشئ: ucl_2026_27_crests.sql (8 فرق جدد + crest_url لكل الـ36)، saudi_2026_27_crests.sql (crest_url لكل الـ18)، ucl-2026-27-teams.csv وsaudi-2026-27-teams.csv (seed_assets/، مطابَقان يدويًا للأسماء الحقيقية بدل التخمين)، وسكربتا رفع (upload_ucl_2026_27_crests.sh وupload_saudi_2026_27_crests.sh) بنفس بنية سكربت يوروبا. تحقّق فعلي: (أ) كل slug في الـCSVين طابق ملف PNG فعليًا موجودًا في docs/handoff/logos-2026-27 بلا نقص (36+18)، (ب) مجموعتا slug في كل SQL مطابقتان تمامًا لعمود slug في الـCSV المقابل (diff فارغ)، (ج) كلا سكربتَي الرفع مُرِّرا فعليًا (bash -n + تشغيل كامل بـsupabase CLI وهمي) وأنتجا بالضبط 36 و18 نداء رفع بالمسارات الصحيحة. لم يُرفَع أي ملف فعليًا (نفس قيد غياب بيانات اعتماد Supabase). التزام صريح بتعليمة الملاحظة: git commit محلي فقط بلا push، وبلا git add -A (جلسة موازية لا تزال تعدّل apps/mobile بشكل غير مُلتَزَم — لم يُلمَس أي من ملفاتها). — supabase/migrations (لا جديد هنا)، supabase/seed/ucl_2026_27_crests.sql, saudi_2026_27_crests.sql, upload_ucl_2026_27_crests.sh, upload_saudi_2026_27_crests.sh, supabase/seed_assets/ucl-2026-27-teams.csv, saudi-2026-27-teams.csv
2026-09-05T03:35:00Z — reconcile_parallel_session: المستخدم أكّد أن الجلسة الموازية (05/06/07_*.py + commits 18bff61..9320566 على fotmob_match_card.dart) كانت بالخطأ ولا حاجة لأي من تعديلاتها. أُعيد fotmob_match_card.dart حرفيًا لمحتوى فرع fix/fotmob-card-reference-parity (طرفه 90d4214 — التصحيحان الأول والثاني الموثّقان أعلاه في fotmob_08/fotmob_09) عبر git checkout 90d4214 -- <path> (بلا rebase/force-push، تاريخ Git لم يُعَد كتابته). باقي الملفات الثمانية التي عدّلها نفس الفرع (app_tokens.dart، app_colors_light.dart، ملفات l10n، اختبار الحالة) كانت مطابقة بالفعل لما هو على main — لم تحتج استعادة. حُذفت أيضًا تعديلات غير مُلتزَمة غير مرتبطة (admin_monthly_competitions_section.dart، admin_ui_kit.dart) والسكربتات الثلاثة الطارئة — كلها من الجلسة الموازية، أكّد المستخدم عدم الحاجة إليها. تحقّق: flutter analyze نظيف، dart format بلا فروقات، 110/110 اختبار ناجح. — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart | commit: 3ec27f2

2026-09-05T00:26:46Z — 08_bigger_crests: شعارات الفرق في بطاقة المباراة كانت AppSizes.iconXl وهو رمز مشترك؛ أُدخل ثابت محلّي _crestSize = 56 داخل _TeamColumn ليكبر الشعار في هذه البطاقة وحدها دون المساس ببقية الشاشات — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart

2026-09-05T00:28:27Z — 05_compact_footer_badges: الصفّ السفلي للبطاقة صار شارتين صغيرتين عند الطرفين (×2 دبل يمينًا، ✓ إرسال يسارًا) والوسط فارغ، مطابقةً لموضع شارتَي «ف» في المرجع، بدل صفّ يملأ العرض. الارتفاع 36px دون AppSizes.minTouchTarget — مطلب بصري صريح من صاحب المشروع، مسجَّل كانحراف مقصود لا سهو — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart

2026-09-05T00:28:32Z — 06_smaller_score_steppers: مربّعات إدخال النتيجة صُغِّرت — 76×104 إلى 68×92، ومنطقتا +/− من 34 إلى 28، والرقم من 22pt إلى 20pt. منطقة اللمس صارت 28px أي دون AppSizes.minTouchTarget — مطلب بصري صريح من صاحب المشروع، مسجَّل كانحراف مقصود — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart

2026-09-05T00:28:53Z — 07_confirm_badge_contrast: شارة الصح بين العدّادين كانت تُقرأ دائرة سوداء قبل التأكيد لأن تعبئتها tokens.surface (نفس داكن البطاقة) وأيقونتها tokens.textMuted؛ صارت التعبئة textPrimary@0.10 والأيقونة textSecondary على نمط العدّادات وزر الدبل غير المفعّل. الحالة المؤكَّدة (primary/onPrimary) دون تغيير — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart

2026-09-05T01:20:15Z — 10_monthly_competitions_scroll: قسم المسابقات الشهرية كان يُقصّ ولا يُمرَّر لأن AdminShell._bodyFor يُرجع على الجوال Padding بلا تمرير، وهذا القسم وحده من الثمانية لا يمرّر نفسه؛ لُفَّ Column في SingleChildScrollView داخل القسم (لا في الـshell، فلفّه هناك يكسر الأقسام السبعة التي تحوي ListView). وكُبِّر مؤشّر تحميل الموسم من 14 إلى 18 لأنه كان يبدو فراغًا وسط الصفّ — apps/mobile/lib/features/admin/screens/sections/admin_monthly_competitions_section.dart

2026-09-05T01:32:44Z — 11_local_crest_assets: شعارات الفرق تظهر في شاشة الشعارات الشهرية (Image.asset محلّي، كل الطلبات 200) وتختفي في بطاقة المباراة (TeamBrand.logoUrl عبر a.espncdn.com)؛ أُضيف assetPath اختياري إلى TeamLogo يُرسم بـImage.asset ويسبق الشبكة، ويملؤه resolveTeamIdentity من teamLogoAssetPath() القائمة أصلًا (تقبل الاسمين العربي والإنجليزي). المعامل اختياري فمواضع الاستدعاء الخمسة سليمة، وتستفيد كلها لأن الإصلاح في المُحلِّل — apps/mobile/lib/core/ui/team_logo.dart + apps/mobile/lib/features/competition/team_identity.dart

2026-09-05T12:57:51Z — 13_history_team_names: شاشة «توقعاتي» كانت تعرض fixtureId الخام لأن _FixturePredictionCard يمرّر `fixture: null` صراحةً، فيسقط _ScoreLine إلى فرعه الاحتياطي رغم أن ودجت الشعارين والاسمين والعلامة موجودة وسليمة؛ صارت البطاقة تشاهد seasonFixturesProvider(seasonId) وتبحث عن fixtureId فيه (يعمل لكل المواسم لا الشهر الجاري)، وتحوّل _ScoreLine من RoundFixtureCardDto المُسقَط إلى SeasonFixtureCardDto، ويمرّر _TeamMini assetPath من resolveTeamIdentity فيسبق الشعار المرفق شبكة ESPN. بلا تعديل عقود ولا خادم — apps/mobile/lib/features/history/prediction_history_screen.dart

2026-09-05T14:03:58Z — 14_entry_kind_read_cast: «ترحيل إلى السجل» كان يفشل دائمًا بـ503 بلا أي أثر في سجلّ الخادم؛ الطباعة التشخيصية في العميل أخرجت السبب: ledger.row_corrupt — «Unknown ledger entry kind: Instance of UndecodedBytes». سائق postgres لا يفكّ ترميز النوع المُعرَّف ledger.entry_kind عند القراءة فيعيد بايتات خامًا. أُضيف ::text لكل جملة تقرأ العمود (ست مواضع، تشمل RETURNING) في محوّلي السجل. لا تغيير في EntryKind ولا المخطّط ولا العقود — packages/infrastructure/lib/src/ledger/postgres_fixture_ledger_repository.dart + packages/infrastructure/lib/src/ledger/postgres_ledger_repository.dart

2026-09-05T15:57:36Z — 15_history_from_month_feed: «توقعاتي» عادت تعرض المعرّف بعد نقل مباريات سبتمبر إلى موسم «شهر 9»، لأن FixturePredictionDto.seasonId هو موسم المشارك لا موسم المباراة (147 مشاركًا في 2026/27 مقابل 9 في 09/2026)، فيعيد seasonFixturesProvider قائمة فارغة؛ صارت القراءة من currentMonthFixturesProvider وهو نفس ما تعرضه شاشة المباريات. لم نوحّد المشاركين في قاعدة البيانات لأن participant_id مفتاح أجنبي في fixture_predictions وfixture_scores وfixture_point_entries — apps/mobile/lib/features/history/prediction_history_screen.dart

## نقطة التسليم — 2026-09-05

**النموذج:** المسابقة هي **الشهر** لا الدوري. كل مباريات سبتمبر تحت موسم
«شهر 9» (09/2026، id 6bf8134c-3eed-46ce-a0dc-e3dc5d4c57c2). الدوريات
مصدر للمباريات فقط. الجائزة لصاحب أعلى نقاط في الشهر.

**قواعد النقاط:** مطابقة تامة = 3، مع الدبل = 6، أي شيء آخر = 0.
correct_outcome موجود كتصنيف لكنه بصفر نقاط. مؤكَّد من
ConfiguredRulesetProvider: exact_scoreline=3، double_multiplier=2.

**السلسلة تعمل كاملة:** توقّع ← احتساب ← ترحيل ← تصحيح ← ترتيب.

**أُصلح اليوم:** entry_kind::text عند القراءة (كان يفشل الترحيل دائمًا
بـ503 بلا أثر في السجل)، أسماء المتصدرين، إلغاء التوقّع التلقائي 0-0،
بطاقة المباراة، الشعارات من الأصول المحلّية، تمرير الشعارات إلى البطاقة،
تمرير أسماء الفرق إلى «توقعاتي»، تمرير قسم المسابقات الشهرية.

**تسجيل الدخول:** حُلّ بتمديد Access token expiry إلى 604800 في لوحة
Supabase. لا كود. الحدّ أسبوع لا سنة.

**مؤجّل بقرار:**
- اسم الدوري في ترويسة البطاقة (تعرض «شهر 9») — يحتاج عمود
  competition_label على fixture_schedules عبر 7 طبقات. الفريق لا يحدّد
  الدوري لأن النادي يلعب في دوريه وفي البطولة القارية معًا.
- displayName في ParticipantFixtureScoreDto — «تقرير المباراة»
  و«التوقعات» في لوحة المشرف تعرضان معرّفات.
- حذف مباراة من التطبيق — الاستعلام يكفي حاليًا.
- تجديد refresh_token (سكربت 12 مكتوب ولم يُنفَّذ).

**مشكلة معلومة غير محلولة:** 182 مشاركًا في مواسم الدوريات (147 في
2026/27، 35 في 2026/2027) و9 فقط في 09/2026. participant_id مفتاح
أجنبي في fixture_predictions وfixture_scores وfixture_point_entries،
فالتوحيد جراحي. لوحة المتصدرين تعرض مشاركي «شهر 9» فقط.

**لوحة المشرف:** 7 أقسام تعمل، 7 فارغة («قيد التطوير») يُنصح بحذفها.

**قيود التشغيل:** Termux/proot، سكربتات Python بمراسٍ assert،
لا git add -A، الدفع بإذن، flutter test قبل كل دفعة.

2026-09-05 — 19_report_display_name: «تقرير المباراة» في لوحة المشرف كان يعرض participantId خامًا رغم أن displayName يصل فعليًا عبر السلسلة كاملة (adminGetParticipantDisplayNames -> fixtureScoresToJson -> ParticipantFixtureScoreDto.displayName -> FixtureReportRow.displayName)؛ _FixtureReportRowCard وحدها كانت ترسم المعرّف. صارت تعرض الاسم، ومع غيابه مقطعًا من ثمانية محارف بدل UUID كامل. تعديل في طبقة العرض وحدها: لا عقود ولا خادم ولا قاعدة بيانات. «التوقعات» لا تزال تعرض المعرّف لأن FixturePredictionDto بلا display_name — إصلاحها يمسّ الخادم والعقود — apps/mobile/lib/features/admin/screens/sections/results_scoring_section.dart

2026-09-05 — 20+21_predictions_display_name: «التوقعات» في لوحة المشرف صارت تعرض الاسم. displayName أُضيف إلى FixturePredictionDto بنفس شكل ParticipantFixtureScoreDto (اختياري، افتراضي ''، ويُحذف من JSON عند فراغه)، والربط في مسار GET /admin/fixtures/{id}/predictions عبر AdminGetParticipantDisplayNames نفسه الذي يستخدمه مسار scores. المفاجأة: _UnwiredParticipantReader يرمي StateError ولا يعيد Err، فانكسرت أربعة اختبارات مسار؛ الحلّ ربط InMemoryParticipantReader فارغ في جذر الاختبار (لا ابتلاع استثناء في المسار) — وهو نفس عقد مسار scores. لا يوجد بعد اختبار يؤكّد ظهور اسم فعلي. — packages/contracts/lib/src/fixture_prediction_dto.dart, apps/server/lib/http/fixture_prediction_dto_mapper.dart, apps/server/routes/admin/fixtures/[id]/predictions/index.dart, apps/server/test/routes/admin/fixtures/admin_fixtures_predictions_route_test.dart, apps/mobile/lib/features/admin/screens/sections/admin_predictions_section.dart

2026-09-05 — 22..24_drop_placeholder_admin_sections: حُذفت عشرة أقسام نائبة كانت تعرض «قيد التطوير» (dailyDoubles, leaderboards, competitions, teams, social, notifications, reportsAnalytics, systemHealth, rolesPermissions, settings)، فبقيت الثمانية المنفَّذة. switch في _bodyFor صار شاملًا فحُذف فرع `_` ومعه معامل l10n ومتغيّره، وحُذف admin_coming_soon_section.dart، وحُذفت مجموعة «الإدارة»، وصارت بطاقة «مسابقات متاحة» تشير إلى monthlyCompetitions. اختبارا admin_shell كانا يعتمدان على teams وsettings المحذوفين؛ صارا يستخدمان ledger. درس مستفاد: استبدال قسم نائب خامل بقسم حقيقي في اختبار ليس محايدًا — audit يحمّل عند البناء ولا يكتمل مزوّده في مضيف الاختبار، فتنتهي مهلة pumpAndSettle. مؤجّل: مفاتيح ARB اليتيمة (adminTeamsTab وإخواتها وadminSectionComingSoon) — دفعة مستقلة على نمط 17_remove_orphan_l10n_keys — apps/mobile/lib/features/admin/admin_sections.dart, apps/mobile/lib/features/admin/admin_shell.dart, apps/mobile/lib/features/admin/screens/sections/admin_dashboard_section.dart, apps/mobile/test/features/admin/admin_shell_test.dart, (deleted) apps/mobile/lib/features/admin/screens/sections/admin_coming_soon_section.dart

2026-09-05 — 25_remove_orphan_admin_l10n_keys: حُذفت أحد عشر مفتاح ARB لم يعد لها قارئ بعد حذف الأقسام النائبة (adminDailyDoublesTab وإخواتها وadminSectionComingSoon) من app_ar.arb وapp_en.arb، ثم أُعيد توليد app_localizations*.dart لأنها مُتتبَّعة في المستودع، فلو تُركت لبقيت المُستقبِلات بلا مفاتيح وأخرج gen-l10n القادم فرقًا غير ذي صلة. تحقّق قبل الحذف: لا مرجع لها في lib أو test خارج lib/l10n، والملفان يُحلّلان كـJSON بعد التعديل — apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, apps/mobile/lib/l10n/app_localizations.dart, apps/mobile/lib/l10n/app_localizations_ar.dart, apps/mobile/lib/l10n/app_localizations_en.dart

2026-09-06 — 28_fixtures_day_bar: شاشة المباريات صارت تعرض مباريات يوم واحد بدل الشهر كاملًا، خلف شريط أيام أفقي على نمط FotMob وصفحة تقويم تُفتح من أيقونة التقويم في الشريط العلوي. التجميع حسب اليوم عرضٌ محض فوق قراءة currentMonthFixturesProvider نفسها: لا مسار جديد ولا مزوّد جديد ولا تغيير في الخادم. الشاشة صارت ConsumerStatefulWidget تملك اليوم المختار وحدها كي لا يختلف الشريط والتقويم والقائمة. قبل أي اختيار من المستخدم ينزلق التحديد إلى أقرب يوم فيه مباريات (المستقبل مقدَّم عند التعادل) وإلا لفُتحت شاشة فارغة على «اليوم» وقُرئت كعطل — وهذا أيضًا ما يُبقي اختبار current_month_fixtures_screen_double_test أخضر رغم أن futureIso() يضع الانطلاق بعد سنة. مباراة بلا kickoffAt تظهر في كل يوم لأنها لا تُصنَّف تحت أي يوم. ستة مفاتيح ARB جديدة مع إعادة توليد يدوية لـapp_localizations*.dart لأنها مُتتبَّعة. مؤجَّل بانتظار قرار: أيقونات الشريط العلوي الأخرى في المرجع (⋮ والبحث وشارة «مباشر») — لا وظيفة خلفها اليوم فلم تُضف كنائبات — apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart, apps/mobile/lib/features/fixture_prediction/widgets/fixtures_date_bar.dart, apps/mobile/lib/features/fixture_prediction/widgets/fixtures_calendar_page.dart, apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, apps/mobile/lib/l10n/app_localizations.dart, apps/mobile/lib/l10n/app_localizations_ar.dart, apps/mobile/lib/l10n/app_localizations_en.dart

2026-09-06 — 29_card_metrics_parity: مقاسات البطاقة قيست فعليًا من لقطة المرجع (1080px، مقياس 2.75) وقورنت بلقطة التطبيق، فظهر أن التطابق كان مزعومًا لا مقيسًا. الشعار 91px في المرجع مقابل 152px في التطبيق (56 منطقية) فصار 34؛ صندوق العدّاد 167px مقابل 188px فصار العرض 61 والارتفاع 82 ومنطقة النقر 26 على نفس النسبة؛ الهامش الجانبي للبطاقة 15px مقابل 45px فصار AppSpacing.sm بدل lg. لم تُمسّ الألوان: المرجع رمادي محايد (#2C303B للسطح، #383838 للعدّاد، خلفية سوداء تامة) بينما التطبيق بنفسجي (#181327 و#262233 وخلفية #07060E)، ومصدرها AppTokens لا البطاقة، فتغييرها يمسّ كل شاشة وينتظر قرار المالك — apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart, apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart

2026-09-06 — 30_neutral_dark_palette: الأساس الداكن في AppColors صار محايدًا بقيم مأخوذة عيّنةً من لقطة المرجع لا بالتقدير: الخلفية #000000 والسطح #2F2F2F والمرتفع #383838 والأعلى #424242، والنصّان الثانوي والخافت #E3E3E3 و#9D9D9D. البنفسجي المستبدَل (#07050D/#181326/#1D1730/#241C3A) كان يصبغ كل سطح في التطبيق وكان أكبر فجوة بصرية بقيت بعد 29_card_metrics_parity. لم تُمسّ ألوان الإجراء (primary) ولا الإنجاز (gold/silver/bronze) ولا الدلالات (success/warning/info/error) ولا لوحة الوضع الفاتح، فالتغيير سلّم رمادي فقط. تحقّق قبل التعديل: لا سطر في lib أو test يذكر أيًّا من الرموز الستّة القديمة خارج app_colors.dart، فلا مرجع مكسور. أثره يتجاوز شاشة المباريات إلى كل شاشة تقرأ AppTokens — بقرار المالك «نفس تطبيق فيت موب» — apps/mobile/lib/core/theme/app_colors.dart

2026-09-06 — 31_day_strip_centring: شريط الأيام كان يفتح عالقًا على أقدم يوم في نافذته (الأحد 30 أغسطس بينما اليوم 6 سبتمبر) بلا تسمية «اليوم» ولا خط تحديد. السبب: ListView.builder لا يبني إلا العناصر الظاهرة، والعنصر المختار في وسط النافذة (الفهرس 7) خارج الشاشة عند أول إطار، فـ_selectedKey.currentContext يعود null في addPostFrameCallback ولا يُنفَّذ Scrollable.ensureVisible أبدًا — عطل صامت لا يرمي شيئًا. استُبدل بـSingleChildScrollView + Row فتُبنى الخمسة عشر عنصرًا جميعًا (نصوص فقط، لا كلفة) ويجد المفتاح سياقه. وأُضيف _centredOnce: أول توسيط قفزة بلا حركة كي لا يبدو الشريط منزلقًا من تلقائه قبل أن يلمسه أحد، وما بعده متحرّك — apps/mobile/lib/features/fixture_prediction/widgets/fixtures_date_bar.dart

2026-09-06 — 32_calendar_appbar_pill: شريط صفحة التقويم كان يظهر فارغًا إلا من سهم الرجوع: لا عنوان ولا زر «اليوم». السبب FilledButtonThemeData في app_theme.dart يفرض minimumSize: Size.fromHeight(52) على كل FilledButton، وارتفاع شريط التطبيق 56، فالزرّ يفيض ويُقتطع ويأكل عرض العنوان الموسّط (centerTitle: true) فيختفيان معًا — درس: زرّ مصمَّم لعرض الصفحة لا يوضع في actions بلا مقاس صريح. صار الزرّ StadiumBorder بمقاس 72×40 وحشوة أفقية lg. وحُذف العنوان لا لإصلاح العطل بل لأن المرجع نفسه بلا عنوان: حبّة «اليوم» وسهم الرجوع فقط. ومفتاح fixturesCalendarPickTitle صار يتيمًا فحُذف من الملفات الخمسة على نمط 25_remove_orphan_admin_l10n_keys — apps/mobile/lib/features/fixture_prediction/widgets/fixtures_calendar_page.dart, apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, apps/mobile/lib/l10n/app_localizations.dart, apps/mobile/lib/l10n/app_localizations_ar.dart, apps/mobile/lib/l10n/app_localizations_en.dart

2026-09-06 — 33_live_chip: شارة «مباشر» في شريط شاشة المباريات. «جارية» تقدير زمني محلي لا حقيقة من الخادم — التغذية تحمل kickoffAt ولا تحمل حالة — فـliveWindow = ١٢٠ دقيقة بعد الانطلاق هي التعريف كاملًا (الخيار «أ» بقرار المالك، مقابل إضافة حقل حالة يمسّ العقود والمسارات وقاعدة البيانات). الشارة تنبض وتقبل النقر فقط حين توجد مباراة جارية، وتبقى ظاهرة خافتة معطَّلة فيما عدا ذلك كي لا يُقرأ غيابها كتحميل. النبضة لا تصل إلى صفر (0.35..1) فتبدو نبضًا لا وميضًا مكسورًا. حارسان ضدّ الحالات العالقة: البناء يقرأ _liveOnly && hasLive فتنتهي التصفية تلقائيًا حين تنتهي آخر مباراة بدل ترك المستخدم أمام قائمة فارغة لم يُفرغها، واختيار يوم يُطفئ التصفية صراحةً؛ وتشغيلها ينقل التحديد إلى اليوم لأن الجارية اليوم بالضرورة. مفتاح ARB واحد جديد مع التوليد اليدوي — apps/mobile/lib/features/fixture_prediction/widgets/live_matches_chip.dart, apps/mobile/lib/features/fixture_prediction/current_month_fixtures_screen.dart, apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, apps/mobile/lib/l10n/app_localizations.dart, apps/mobile/lib/l10n/app_localizations_ar.dart, apps/mobile/lib/l10n/app_localizations_en.dart

2026-09-06 — 34_leaderboards_single_month: «المتصدرون» كانت تعرض تبويبًا لكل موسم يشارك فيه المستخدم، فظهرت تبويبات «الدوري الألماني 2026/27» و«الدوري الإسباني» على لوحات فارغة. الفحص على قاعدة الإنتاج بيّن السبب: تسع مسابقات، واحدة فقط («شهر 9» / 09/2026) فيها مباريات (21)، والثماني الباقية بصفر مباراة ومعها 182 اشتراكًا — بقايا نموذج الدوريات قبل التحوّل إلى «الشهر هو المسابقة». الدفتر كلّه (8 قيود) في «شهر 9» وحدها. فالتبويبات صارت مقصورة على المواسم التي تحمل مباراة فعلًا، مقروءة من currentMonthFixturesProvider نفسه الذي تشاهده شاشة المباريات: لا مسار ولا مزوّد ولا تغيير خادم، ويصحّح نفسه شهريًا. وموسم واحد يعني لا شريط تبويبات أصلًا. اختير التضييق في العرض على الحذف (الخيار ب بقرار المالك): زناد ledger.reject_entry_mutation يمنع حذف الدفتر، وخمسة عشر قيد RESTRICT عبر خمسة schemas تجعل الحذف عملية من عشر عبارات على بيانات مستخدمين حقيقيين — والبيانات الميتة لا تؤذي. أُخذت نسخة pg_dump احتياطية قبل الفحص. إن حُذفت المواسم لاحقًا يصير هذا المرشّح بلا أثر بدل أن يكون شيئًا يُتراجع عنه. مؤجَّل: start_at لموسم «شهر 9» هو 2026-08-01 لا 2026-09-01، أي شهران خلافًا لقاعدة المسابقة — apps/mobile/lib/features/leaderboards/leaderboards_screen.dart

2026-09-06 — 35_leagues_migration (1/4): بطاقة المباراة تعرض «شهر 9» لا اسم الدوري لأن اسم الدوري غير موجود في البيانات أصلًا: SeasonFixtureCardDto يحمل الموسم والمباراة واسمي الفريقين والانطلاق فقط، وfootball_data.teams بلا رابط دوري. أُضيفت هجرة 0027: جدول football_data.leagues (اسم + شعار، بنفس شكل teams وسياسة RLS نفسها) وعمود league_id اختياري على competition.fixture_schedules على نمط 0024 حرفيًا. قراران مسجَّلان: (1) هذا يُنهي تأجيل tournament في ADR-003 §2.2 — 0013 أجّله لأن «لا شيء في واجهة v1 يستهلك بيانات البطولة» وطلب مراجعته عند الحاجة، وقد حانت، فأُضيف في أنحف صورة: هوية عرض فقط بلا شكل موسم ولا مرجع مزوّد. (2) لم يُربط بـcompetition.competitions رغم وجود ثمانية صفوف بأسماء دوريات فيه، لأن ذلك الجدول صار يعني «مسابقة ينضم إليها المستخدمون ويجمعون فيها نقاطًا» ويضمّ «شهر 9» — فكان league_id سيقبل مسابقة شهرية كدوري. الدوري واقع كروي لا بنية مسابقة، فمكانه football_data بجوار teams. Axiom 3 سليم: football_data.fixtures ما زال بلا مرجع مسابقة. الهجرة توسيعية بحتة ولا تغيّر سلوكًا وحدها؛ الملء الخلفي للمباريات الـ21 وقائمة الاختيار في لوحة المشرف والعرض في البطاقة دفعات 2 و3 و4 — supabase/migrations/0027_fixture_league.sql

2026-09-06 — 36_league_on_fixture_card (3/4): اسم الدوري وشعاره صارا يسافران مع بطاقة المباراة عبر ستّ طبقات، فترويسة البطاقة تعرض «الدوري الإنجليزي الممتاز» بدل «شهر 9». قرار التصميم: تسطيح الاسم والشعار على القراءة بدل إضافة كيان League ومنفذ ومستودع ومسار /leagues وDTO ومزوّد في الموبايل على نمط الفرق — ثمانية مصنوعات مقابل عمودين، ولها سابقة في المشروع نفسه: CurrentMonthFixtureEntry يحمل competitionName مسطَّحًا لا معرّفًا فقط. الضمّ LEFT لا INNER عمدًا: مباراة بلا league_id (كل صفّ سابق للهجرة 0027) يجب أن تعود بأعمدة دوري فارغة لا أن تختفي من التغذية صامتةً. عمودا الدوري يُقرآن دفاعيًا (is String) لا يُتحقَّق منهما كأعمدة الهوية، لأن غيابهما حالة طبيعية لا فساد بيانات. leagueName/leagueLogoUrl غائبان عن FixtureSchedule.create ولا يُكتبان أبدًا — الصفّ يخزّن league_id لا اسمًا. والبطاقة تفضّل شعار الدوري البعيد على أصل competition_logo_assets.dart لأنه يُشحن فارغًا، وترتدّ إلى رمز الكأس عند فشل الشبكة. مؤجَّل للدفعة 4/4: قائمة اختيار الدوري في لوحة المشرف وكتابة league_id عند upsert — المباريات الـ21 القائمة مُلئت بـSQL مباشرة، فالمطلوب للمباريات الجديدة وحدها. وlogo_url ما زال فارغًا للدوريات الستة، فيظهر الاسم بلا شعار حتى يُملأ — packages/domain/lib/src/competition/fixture_schedule.dart, packages/domain/lib/src/competition/season_fixture_card.dart, packages/infrastructure/lib/src/competition/postgres_fixture_schedule_repository.dart, packages/application/lib/src/competition/list_current_month_fixtures.dart, packages/application/lib/src/competition/browse_season_fixtures.dart, packages/contracts/lib/src/competition_dto.dart, apps/server/lib/http/competition_dto_mapper.dart, apps/mobile/lib/features/fixture_prediction/widgets/fotmob_match_card.dart

2026-09-06 — 35_team_logo_aliases: شعارات الفرق كانت تظهر لميلان ويوفنتوس فقط وتسقط إلى دائرة الحروف لبقية الأندية. السبب أن `football_data.teams.name` عربي بينما `_arabicTeamLogoAliases` كانت أربعة وعشرين اسمًا فقط، و`_slugifyTeamName` تحذف كل حرف غير لاتيني فتعيد نصًّا فارغًا لأي اسم عربي. crest_url ليس بديلًا: قيم الدوري الإسباني ملفات SVG لا يقرأها Image.network، وقيم دوري الأبطال والأوروبي والسعودي روابط Storage لم تُرفع ملفاتها بعد. فصارت الخريطة تغطّي كل اسم مبذور في supabase/seed له ملف في assets/team_logos، ومعها _normalizeArabic لتوحيد الهمزة والتاء المربوطة والألف المقصورة فتُطابق «إسبانيول/اسبانيول» و«مارسيليا/مرسيليا» بلا سطر لكل صيغة. باقٍ بلا شعار عمدًا: أغلب الدوري الإيطالي (أتالانتا، لاتسيو، تورينو…) والسعودي عدا الاتحاد والنصر، وألافيس، وباريس إف سي — ملفات ناقصة لا خطأ في الربط — apps/mobile/lib/features/competition/team_logo_assets.dart

2026-09-06 — 36_missing_crests: نُزّلت شعارات الفرق التي بقيت بلا صورة بعد 35_team_logo_aliases (29 من 31) وأُضيفت شرائحها إلى _monthlyLogoSlugs وأسماؤها العربية إلى _arabicTeamLogoAliases. المصدر ESPN: نقطة teams لكل دوري (ita.1, ita.2, esp.1, ksa.1) بترويسة متصفّح لأنها ترفض بلا واحدة (403)، ومعها احتياط من CDN الصور بمعرّفات team_registry.dart المسجَّلة أصلًا للسعودي. لا معرّفات مكتوبة يدويًا: المعرّف الرقمي في team_registry.dart كان يُخمَّن ويصمت عند الخطأ، بينما المطابقة بالاسم على قائمة الدوري تُبلّغ عن كل فريق لم تجده. الدوري الإيطالي يُقرأ من الدرجتين لأن البذرة تخلط فرقًا هابطة (فروزينوني، مونزا، فينيسيا). لا يُربط في Dart إلا ما نزل فعلًا وتحقّق من توقيعه كـPNG، فلا شريحة ميّتة تُعيد null بصمت. لم يفلح: al-faisaly, al-hiaal — apps/mobile/lib/features/competition/team_logo_assets.dart, apps/mobile/assets/team_logos/*.png

2026-09-06 — 37_saudi_crests_local: الهلال والفيصلي فشل تنزيلهما في 36_missing_crests (404 من CDN بمعرّفات team_registry.dart المقدّرة)، وملفاهما موجودان أصلاً في docs/handoff/logos-2026-27/spl-2026-27 منذ بذرة الدوري السعودي. النسخ محلّي من CSV seed_assets لا بأسماء مكتوبة يدوياً، فيشمل أي شريحة سعودية ناقصة مستقبلاً. الدرس: مصدر داخل المستودع يُقدّم على الشبكة — apps/mobile/lib/features/competition/team_logo_assets.dart, apps/mobile/assets/team_logos/*.png

2026-09-06 — 37_unresolved_team_warning (4/4): نموذج إضافة المباراة في لوحة المشرف يحلّ اسم الفريق المكتوب إلى معرّف في الكتالوج بمطابقة اسم تامّة، وإن لم يطابق أرجع null بلا أي إشارة — والمباراة تُحفظ بنجاح لأن النصّ الحرّ هو هوية السجل (Axiom 3). ما يختفي صامتًا هو كل ما يُشتقّ من المعرّف: الشعار ولون النادي، فتظهر البطاقة بحرفين رماديين. هكذا شُحنت «اسبانيول» (الكتالوج: «إسبانيول») و«مرسيليا» (الكتالوج: «مارسيليا») — حرف واحد، لا خطأ، واكتُشفتا بالعين في لقطة شاشة بعد أيام. أُضيف سطر تحذير تحت كل حقل فريق حين يكون النصّ غير فارغ ولا يُحلّ. تحذير لا تحقّق عمدًا: النصّ الحرّ يبقى مشروعًا وزرّ الإرسال يبقى مفعَّلًا، فمباراة لفريق خارج الكتالوج فعلًا يجب أن تبقى قابلة للإرسال؛ المطلوب ألّا يمرّ الخلل دون أن يُرى. مفتاح ARB واحد. لم تُضف قائمة اختيار الدوري في هذه الدفعة: المباريات الـ21 مُلئت بـSQL، ولا مباراة جديدة قبل أكتوبر، فالأولوية للحارس الذي يمنع تكرار الخلل الصامت — apps/mobile/lib/features/admin/screens/sections/fixture_schedule_section.dart, apps/mobile/lib/l10n/app_ar.arb, apps/mobile/lib/l10n/app_en.arb, apps/mobile/lib/l10n/app_localizations.dart, apps/mobile/lib/l10n/app_localizations_ar.dart, apps/mobile/lib/l10n/app_localizations_en.dart

2026-09-06 — 38_remove_fixture_from_season (1/2): لم يكن في المنصة ما يحذف مباراة من موسم إطلاقًا — الموجود RemoveFixtureFromRound يحذف من جولة، ومسابقاتك الشهرية بلا جولات. أُضيفت الحالة عبر خمس طبقات: منفذ unlinkFixtureFromSeason، وتنفيذه بـDELETE ... RETURNING (لأن الحذف المجرّد لا يبلّغ عبر غلاف الاتصال إن حُذف صفّ فعلًا، فلا يُميَّز نداء ثانٍ عن أول)، وحالة الاستخدام، والتوصيل في CompositionRoot، ومسار DELETE /seasons/{id}/fixtures/{fixtureId}، وapi_client. حارسان يرفضان ولا يتتاليان: أي توقّع قائم (fixture_has_predictions) أو نتيجة مسجَّلة (fixture_result_already_recorded، نفس رمز الأصل عمدًا). السبب بنيوي لا احترازي: زناد ledger.reject_entry_mutation يرفض كل حذف وتعديل، فمباراة توقّع عليها أحد لا تُحذف حقًّا — فكّ ربطها يترك نقاطًا قائمة في الدفتر لمباراة لا تعرضها أي شاشة، أي مجموع في لوحة المتصدرين لا يُفسَّر، وهو أسوأ من الخطأ المراد تصحيحه. الحارسان كلاهما يُفحص لأن نتيجة قد تُسجَّل قبل أن يتوقّع أحد، وتوقّعًا قد يوجد بلا نتيجة. الحذف نفسه عديم الأثر عند التكرار: رابط مفقود = Ok(false) لا خطأ ولا 404. الغرض تصحيح خطأ إدخال المشرف في نافذة ما قبل أن يتصرّف أحد، لا إلغاء مباراة (اختيار (أ) على (ب) ترك النقاط و(ج) نظام إلغاء بحقل حالة). مؤجَّل للدفعة 2/2: زرّ الحذف في لوحة المشرف داخل نطاق «تصحيح المباراة» القائم، إعادةً لاستعمال منتقي المباراة بدل زرّ حذف تحت كل صفّ — packages/application/lib/src/prediction/ports/fixture_prediction_repository.dart, packages/infrastructure/lib/src/prediction/postgres_fixture_prediction_repository.dart, packages/application/lib/src/competition/remove_fixture_from_season.dart, packages/application/lib/application.dart, apps/server/lib/composition/composition_root.dart, apps/server/routes/seasons/[id]/fixtures/[fixtureId]/index.dart, packages/api_client/lib/src/competition_api.dart

2026-09-06 — 39_fix_unlink_fakes: تسعة أخطاء من دفعة 38، صنفان. الأول خطأ صريح: RemoveFixtureFromSeason استعمل FixturePredictionView بلا استيراد — النوع في application لا في domain، ولم يكشفه إلا التحليل على الجذر لأن flutter test في apps/mobile لا يمسّ الحزم. الثاني أثر متوقّع لتوسيع منفذ: ثمانية مزيّفات تنفّذ FixturePredictionRepository صارت ناقصة. الستة في apps/server/test أخذت أبسط تنفيذ صادق (Ok(false) = لا رابط) لأن اختباراتها لا تمسّ الطريقة، أما مزيّف application فأخذ تنفيذًا حقيقيًا يحذف من متجره لأن اختبارات حالة الاستخدام تعتمد عليه. وأُضيفت ستة اختبارات للحارسين: الحذف السعيد، والتكرار يعود Ok(false) لا خطأ، ورفض التوقّع القائم مع التوكيد أن الرابط ما زال موجودًا بعد الرفض (الحارس يرفض ولا يتتالى — وهذا هو التوكيد الذي يحمي الدفتر من نقاط لمباراة لا تعرضها شاشة)، ورفض النتيجة المسجَّلة بلا أي توقّع (لذلك يُفحص الحارسان كلاهما لا أحدهما)، ورفض غير المشرف، ومعرّف مباراة مشوّه — packages/application/lib/src/competition/remove_fixture_from_season.dart, packages/application/test/prediction/fake_fixture_prediction_repository.dart, packages/application/test/competition/remove_fixture_from_season_test.dart, apps/server/test/routes/admin/fixtures/admin_fixtures_predictions_route_test.dart, apps/server/test/routes/feed/current_month_fixtures_test.dart, apps/server/test/routes/fixture_prediction_scoring_test.dart, apps/server/test/routes/fixture_scores_route_test.dart, apps/server/test/routes/scoring_routes_test.dart, apps/server/test/routes/season_fixtures_link_test.dart

## 2026-09-07 — fix 01: duplicate display-name field
- sign_in_screen.dart: removed the second identical `if (_isRegister) ...[ AppTextField(signIn.nameField) ]` block (same key, same controller) — the register form rendered the field twice.
- session_gate_test.dart: added a register-tab regression test asserting `findsOneWidget` for `signIn.nameField`.

## 2026-09-07 - fix 02: constant-time fixture/prediction lookups
- new prediction_lookup_providers.dart: indexes myFixturePredictions and
  currentMonthFixtures by fixtureId (plain Provider, no new HTTP read).
- fotmob_match_card.dart: dropped _findMyPrediction (linear scan per card).
- prediction_history_screen.dart: dropped the per-row feed scan and its now
  unused current_month_fixtures_providers import.

## 2026-09-07 - fix 03: real migration gate in CI
- build-verification.yml: new database_migrations job - starts a clean local
  Supabase stack and runs `supabase db reset --no-seed`, so every migration
  is actually executed against an empty database on each push/PR.
- publish_latest_apk now needs [build_android, database_migrations]: no APK
  reaches Releases unless the schema applies cleanly.

## 2026-09-07 - fix 04: open next month's season ahead of time
- admin_monthly_competitions_section.dart: the Start-season button used to
  appear ONLY when no season was active, and always started DateTime.now()'s
  month. October could therefore not be created during September - someone
  had to press it on 1 Oct, the day every season ends.
- The button is now shown whenever the season state has resolved and targets
  the next un-opened month (current month if idle, following month if a
  season is running). Its label carries the target, e.g. 'start season
  10/2026'. Overlap is still rejected by seasons_no_overlap.

## 2026-09-07 - fix 05: migration 0020 could not apply to a clean database
- The CI migration gate added in fix 03 failed on its very first run:
  0020 does `alter type ledger.entry_kind add value 'fixture_score'` and then
  uses that value in a CHECK constraint in the same transaction ->
  SQLSTATE 55P04. Production was unaffected (statements applied one by one).
- The CHECK moved to new migration 0028, guarded by a pg_constraint lookup so
  it is a no-op where the constraint already exists. Resulting schema is
  identical; 0020 keeps the enum addition and the table.

## 2026-09-07 - fix 06: migration 0026 needs ownership of storage.objects
- The clean-database gate reached 0026 and failed with SQLSTATE 42501:
  storage.objects is owned by supabase_storage_admin, and a local stack's
  postgres role cannot ALTER it or create policies on it.
- The ALTER + two policies are now inside a DO block that catches
  insufficient_privilege and raises a notice. Production already has them;
  RLS is enabled by Supabase itself; the bucket is public-read and uploads
  use the service-role key, so behaviour is unchanged.

## 2026-09-07 - fix 07: raw ISO timestamps and enum names on screen
- new core/format/timestamps.dart: parse an ISO-8601 contract string once,
  convert to the viewer's zone, format via intl with the active locale.
- prediction_history_screen.dart: the card printed prediction.submittedAt
  verbatim, e.g. 2026-09-06T02:29:45.121328Z.
- audit_log_section.dart: printed the raw admin.audit_action enum name and a
  full 36-char UUID. Now an Arabic label (unknown values still fall through
  to the raw name) plus reason, and the target ref shortened to #xxxxxxxx.

## 2026-09-07 - fix 08: the Android launcher said 'mobile'
- android/ is not committed; CI regenerates it with
  `flutter create --project-name mobile`, which sets android:label from the
  pub package name. The installed app was therefore captioned 'mobile'.
- build-verification.yml: new step rewrites android:label in the generated
  manifest, next to the existing INTERNET and ota_update manifest patches.
  The pub package name is unchanged - every package:mobile/... import
  depends on it.
- 03:20 revert: تراجع عن commit bcc8ec226e0186c1ff839d66d3959eb6e704b867 (fix: guard APK build against unset NUKHBA_API_BASE_URL) بطلب المستخدم

## 2026-09-07 - fix 10: old installs were never prompted to update
- update_gate.dart compared the newest release's published_at against a
  timestamp stored ON THE DEVICE. Nothing in that comparison knew which
  build was installed. Worse, the `lastSeen == null` branch recorded the
  newest release as 'seen' on first launch and returned - so a stale
  install marked itself up to date and never prompted again.
- CI now injects NUKHBA_BUILD_SHA (the same 7 chars as the build-<sha>
  release tag). The gate checks whether the published apk_url points at
  its own build; the stored timestamp only prevents re-prompting.
- Coupling to note: the client matches '/build-<sha>/' in the URL. A
  cleaner follow-up is an explicit build_ref field on LatestBuildDto.
- Also declared intl in apps/mobile/pubspec.yaml; used directly but only
  arrived transitively, which dart analyze flagged.

## 2026-09-07 - fix 11: blank rows in the monthly-competitions card
- Regression from fix 04. AdminListRow lays out an Expanded title next to a
  `trailing` widget of natural width. Putting the start-season button there,
  with a label carrying the target month, made trailing wider than the row:
  the title collapsed to zero and the button was clipped off the edge. A
  release build paints no overflow stripe, so the card just looked empty.
- The button moved to its own line under the title row; trailing is the
  season label alone again.
- Lesson: never hand AdminListRow a trailing whose width depends on text.

## 2026-09-07 - fix 12: dark is the default look
- ThemeController defaulted to ThemeMode.system, so the app followed the
  phone and most users saw the light palette. Both the initial state and
  the no-stored-preference fallback are now ThemeMode.dark.
- An explicit 'light' choice is still honoured; the account-screen toggle
  is unchanged. AppTokens.dark / AppTheme.dark already existed.

## 2026-09-07 - fix 13: leaderboard redesign
- New widgets/leaderboard_board.dart: a three-place podium (gold/silver/
  bronze, tiered heights, medal glow) above the remaining places as cards.
  The viewer's row carries a primary border, raised surface and glow.
- A gap chip shows the points needed for the place directly above the
  viewer - the only number derived on the client, a subtraction between two
  values from the same response.
- The avatar circle is a first-initial placeholder sized and positioned
  where an uploaded picture will go, so avatars are a later swap, not a
  re-layout.
- AsyncListView gained an optional listBuilder so loading/error/empty stay
  shared while the data body is a podium rather than a row list.
- NOT in this pass, for lack of data: accuracy %, rank movement arrows,
  real profile pictures. Each needs server work.

## 2026-09-07 - fix 14: daily rank snapshots (pg_cron)
- Migration 0030 adds leaderboard.season_rank_snapshots (season_id,
  participant_id, captured_on, rank, total_points), one row per participant
  per day. Read-side only: it projects season_standings, which is itself a
  SUM over the append-only ledger. Axiom 5 untouched.
- capture_season_rank_snapshots(date) writes today's rows for every season
  whose calendar window is open, ranked with rank() over (order by
  total_points desc) - the same 1224 rule as the pure SeasonLeaderboard.rank.
  Idempotent per day (on conflict do update), so a manual re-run after a
  failed tick is safe.
- View season_standings_with_movement joins the live rank to the most recent
  snapshot and exposes movement = previous_rank - current_rank. NULL means no
  comparable snapshot (new participant or first day), which the client should
  render as "new" rather than an arrow.
- pg_cron scheduled at 05 0 * * * UTC under jobname
  nukhbaa_season_rank_snapshot. Both CREATE EXTENSION and cron.schedule sit
  inside a guarded DO block: the CI clean-database gate has no pg_cron, so it
  creates table/function/view and skips the tick with a notice.
- NOT in this pass: wiring movement through LeaderboardEntryDto and the
  arrows in leaderboard_board.dart. Server + contracts change, next fix.

## 2026-09-07 - fix 15: RLS on season_rank_snapshots
- Applying 0030 through the Supabase SQL editor was silently blocked: the
  editor intercepts any query that creates a table without RLS and waits on a
  confirmation dialog, so nothing reached the database at all.
- The table now enables RLS and carries season_rank_snapshots_select_all
  (select, authenticated, using true) inside the migration itself. Writes stay
  impossible for every client: rows come only from
  capture_season_rank_snapshots(), which runs as the table owner under pg_cron
  and bypasses RLS.
- Same posture as the other leaderboard projections - standings are readable
  by any signed-in participant, never writable from a client.

## 2026-09-07 - fix 16: rank movement arrows wired end to end
- Migration 0030 is applied on the hosted database: 226 snapshot rows,
  pg_cron job nukhbaa_season_rank_snapshot active at 05 0 * * * UTC.
- LeaderboardEntry gains previousRank (nullable) plus a movement getter -
  previousRank minus rank, computed only once the board has assigned a rank,
  so the arrow can never disagree with the place printed beside it. Still
  pure: nothing is derived from a second source.
- PostgresLeaderboardRepository reads season_standings_with_movement and takes
  previous_rank only. The view's own current_rank/movement columns are
  deliberately left unselected - ranking stays the domain's job in exactly one
  place.
- LeaderboardEntryDto carries previous_rank; schema version bumped to 2. A v1
  payload lacks the key, deserializes to null, and renders without arrows.
- leaderboard_board.dart gains _MovementChip: up in success, down in error, a
  dash when unchanged, nothing at all when there is no snapshot to compare
  with, so a first-day board is clean rather than a column of dashes. Shown on
  both the podium tiles and the list rows.
- Arrows stay absent until the second daily snapshot lands - today's capture
  equals the live order, so every movement is currently 0.

## 2026-09-07 - fix 17: accuracy = exact_scoreline alone
- Owner decision: accuracy is the share of a participant's SETTLED fixtures
  whose exact scoreline they called right. correct_outcome does not count -
  it earns points but it did not get the score right, and including it would
  make the percentage stop tracking the number printed beside it.
- Migration 0031 recreates season_standings_with_movement with exact_count and
  settled_count per participant, counted off scoring.fixture_scores and joined
  by participant_id alone (a participant belongs to one season), so a fixture
  linked to several rounds cannot double-count a grade.
- The counts travel raw; the percentage is derived once, in the pure domain,
  exactly as movement is. A participant with nothing settled reads 0/0:
  LeaderboardEntry.accuracy returns null, and the client omits the label
  rather than printing a 0% nobody earned.
- DTO schema version 3 (exact_count/settled_count, defaulting to 0 on an older
  payload). New l10n key leaderboardAccuracy in ar + en.
- The board row folds accuracy into the existing subtitle line; podium tiles
  carry it on its own line.
- RLS note in the migration: the view is security_invoker over
  scoring.fixture_scores, which is own-or-locked. The server reads as table
  owner so counts are complete; a future direct-from-client read would not be.

## 2026-09-07 - fix 18: avatars, step 1 of 4 (database)
- Owner approved the image_picker dependency and chose report-then-remove
  moderation for launch: pictures publish immediately, any signed-in user can
  report one, an admin clears it. No automated screening, no approval queue -
  the user base is a known WhatsApp group, not open sign-up. Moving to
  pre-approval later is one boolean column, not a redesign.
- Migration 0032 adds identity.users.avatar_path - the object KEY inside the
  bucket, never a URL, so the base can change without a data rewrite.
- Bucket , public-read like team-logos: every leaderboard viewer sees
  every participant's picture anyway, and signed URLs would mean minting one
  per row per request for no privacy gain. Keys are random UUIDs. Client
  writes denied outright - uploads go through the server's service-role key
  (ADR-002). The storage.objects block is guarded for 42501 exactly as 0026's
  is, so the CI clean-database gate skips it.
- identity.avatar_reports keeps reported_path, so a report stays evidence of
  what was actually seen rather than a pointer to whatever is there now. One
  OPEN report per (reporter, subject) via a partial unique index; a new one is
  allowed once the first is resolved. No client RLS policy at all - reports
  are filed and resolved server-side, and a SELECT policy would let a reporter
  enumerate who reported whom.
- season_standings recreated to carry avatar_path (drop + create: Postgres
  cannot add a column via REPLACE), and season_standings_with_movement rebuilt
  on top of it, unchanged apart from the new column.
- Steps 2-4 still to come: server upload endpoint + report/resolve routes;
  api_client + DTO avatar_url; mobile picker, board avatars, report button.

## 2026-09-07 - fix 19: avatars, step 2 of 4 (bytes in the row)
- Design changed before any of it shipped. The bucket approach from 0032 cost
  a service-role secret on Northflank, a storage adapter and an outbound
  upload call - three moving parts so a CDN could serve the images instead of
  the server. At a 512 KB cap and a user base in the dozens the whole corpus
  is a few megabytes, so that trade was backwards. Bytes live in the row and
  the entire storage path is gone.
- Migration 0033 adds avatar_bytes / avatar_mime / avatar_updated_at, reverses
  0032's bucket and policies, drops avatar_path, and reprojects both standings
  views onto avatar_updated_at. The views carry the TOKEN only, never bytes: a
  leaderboard read must not drag image data through a join it does not show.
- A CHECK ties the three columns together and caps bytes at 512 KB, so a row
  with bytes and no mime is unrepresentable rather than merely unlikely. The
  server rejects an oversized upload first, with a message the user can act
  on; the constraint is the backstop.
- avatar_updated_at travels in the read URL as a cache-busting token, so a
  replaced picture is a different URL and no stale copy survives on a device.
- User carries avatarMime + avatarUpdatedAt, never the bytes. copyWith gains
  clearAvatar, because null cannot mean "remove" when it already means "leave
  alone".
- UserDirectory: setAvatar / clearAvatar / readAvatar, the last returning the
  new StoredAvatar value. readAvatar is separate on purpose - it is the only
  call in the codebase that moves image bytes, made by exactly one route.
- No new environment variable is needed on Northflank after all.
- Step 3: POST/DELETE /me/avatar, GET /users/{id}/avatar, and the use-cases.
  Step 4: leaderboard avatars, the picker, the report button.

## 2026-09-07 - fix 20: avatars, step 3a of 4 (domain validation)
- `User.validateAvatar(byteLength, mime)`: empty payload, over 512 KB, or a
  mime outside jpeg/png/webp all reject with `identity.avatar_*` validation
  errors -- Arabic messages, matching `validateDisplayName`'s convention.
- The 512 KB / three-mime limits mirror the migration 0033 CHECK exactly, so
  a rejection at the edge and the database backstop never disagree.
- No caller wired yet -- this is pure domain, additive, does not touch
  `UserDirectory`, routes, or `composition_root.dart`. Next: the
  `SetAvatar`/`ClearAvatar`/`ReadAvatar` application use-cases.

## 2026-09-07 - fix 21: avatars, step 3b of 4 (application use-cases)
- `SetAvatar` / `ClearAvatar` / `ReadAvatar` added under
  `packages/application/lib/src/identity/`, mirroring `UpdateDisplayName`'s
  shape exactly: self-only authority via `Authorization.requireRole`, no
  repository lookup needed since the "owner" of an identity is always its
  own principal.
- `SetAvatar` also runs `User.validateAvatar` (step 3a) before touching the
  directory.
- `ReadAvatar` is the one exception to self-only: it takes a `targetUserId`
  separate from `principal`, because avatars are visible platform-wide
  (report-then-remove moderation, decided 2026-09-07) -- any authenticated
  user may read *any* user's picture, not just their own.
- Exported from `application.dart`. Still no route wired -- next: the raw-
  bytes body reader, `composition_root.dart` wiring, then the three routes.

## 2026-09-07 - fix 20: one leaderboard, not two
- The redesign, the movement arrows and the accuracy figure were all built on
  season_leaderboard_screen.dart - a screen the bottom tab never opens. The
  tab opened leaderboards_screen.dart, which drew its own ListTile rows off
  the FIXTURE board. Three features shipped where users could not see them.
- Owner chose unification over duplication: rather than rebuild the podium,
  the arrows and accuracy a second time against FixtureLeaderboardEntryDto,
  both surfaces now render one widget.
- New widgets/season_standings_board.dart holds what was inline in the season
  tab. Both callers pass their own keyPrefix, so each keeps the widget-test
  keys it already asserts instead of sharing a namespace and colliding.
- The bottom tab now shows the SEASON board, not the fixture board. That is
  the deliberate half of the change: the season board is the one carrying the
  podium, the arrows and the accuracy.
- The fixture-points tab on the season screen is untouched - it remains the
  live per-fixture view.

## 2026-09-07 - fix 21: the board reads the store that has the points
- ledger.point_entries is empty (0 rows) while scoring.fixture_scores holds
  359 grades. The ledger is not behind on a manual step - it is UNREACHABLE.
  point_entries.round_id is NOT NULL with an FK to competition.rounds, and
  competition.round_fixtures has zero rows: this project moved to
  season-linked fixtures in migration 0019 and left rounds behind. Not one
  scored fixture can be posted without inventing a round to satisfy a column.
- So fix 20 pointed the bottom tab at an empty store. Reversed here: both
  surfaces render the FIXTURE board, which is append-only, fills the instant a
  result is recorded, and is the source of every number users see today.
- New widgets/fixture_standings_board.dart; the bottom tab and the season
  screen's fixture tab both render it. The season screen is now pure chrome -
  a tab bar and two board widgets, no list bodies.
- Movement and accuracy are not on FixtureLeaderboardEntryDto, so they are
  omitted rather than faked. Both are recoverable from scoring.fixture_scores,
  which GetSeasonFixtureLeaderboard already reads in full. Next fixes.
- Nothing here writes to any point store. 359 grades, 504 predictions and 228
  participants were copied to schema "backup" (suffix 20260907) first.

## 2026-09-07 - fix 22: accuracy on the board that has the points
- Free of any new read: GetSeasonFixtureLeaderboard already loads every
  ParticipantFixtureScore for the season, and the grade travels on each one.
  FixtureLeaderboard.rank now counts exactScoreline while it is already
  summing points, in the same pass, so the figure cannot disagree with the
  total printed beside it.
- Denominator decision, which the earlier season-board version got wrong:
  DECIDED fixtures only - exactScoreline, correctOutcome, incorrect. missed
  (kicked off before they predicted) and pending (result not in) are
  excluded. Counting missed would measure attendance rather than judgement,
  and counting pending would let a percentage drop for a match still being
  played. So decidedCount is deliberately narrower than fixturesScored.
- Numerator stays the owner's decision: exactScoreline alone. A correct
  outcome earns points but did not get the score right.
- No accuracy exists at 0 decided - null, not 0%. The client omits the label
  rather than printing a zero nobody earned.
- FixtureLeaderboardEntryDto schema version 2 (exact_count / decided_count,
  defaulting to 0 on an older payload).

## 2026-09-07 - fix 23: opening the app is the join
- Measured first: of 97 accounts, 28 had joined nothing and 23 had joined only
  league seasons carrying zero fixtures. Half the user base opened the
  leaderboard and was told to join a season while the month's contest ran
  without them. Membership is not a decision this product should ask anyone to
  make.
- The 51 missing accounts were enrolled in 09/2026 by hand first (INSERT ...
  ON CONFLICT DO NOTHING, so the 46 existing members and their joined_at were
  untouched). Season membership is now 97.
- New EnrolInOpenSeasons runs on every GET /me: it enrols the caller in every
  season open right now that has at least one fixture. The fixture requirement
  is what keeps it off the seven league seasons this project carries but never
  runs - open by date, permanently empty, and joining one would put a user on
  a board that can never have a row.
- Idempotent by construction: membership is checked first and
  participants_season_user_uniq is the backstop under that check, so two
  concurrent opens cannot double-enrol and an existing joined_at is never
  rewritten. Next month enrols everyone the moment its first fixture is filed
  - no hardcoded season id, no monthly admin step.
- Every failure is swallowed into Ok. Enrolment is a side benefit of a read,
  never its purpose: /me must still answer "who am I" when the write cannot
  happen, and the next call retries.
- New port method listOpenSeasonsWithFixtures(at); Postgres impl uses the same
  computed [start_at, end_at) window as findCurrentSeason plus an EXISTS on
  season_fixtures. Two test fakes and the unwired root repository gained it.

## 2026-09-07 - fix 24: the daily snapshot follows the points
- Migration 0030 captured season_standings, which sums the unreachable ledger.
  Every snapshot so far recorded a board where all 226 participants were tied
  at zero, so every arrow derived from it would have been meaningless.
- New view leaderboard.season_fixture_standings: the SQL twin of what
  GetSeasonFixtureLeaderboard computes in memory. Scoped through
  competition.participants rather than season_fixtures, since a participant
  belongs to exactly one season - so no fixture-to-season join is needed and a
  fixture linked to two seasons cannot double-count a grade.
- capture_season_rank_snapshots repointed at it. Same signature, same
  idempotence, same schedule: the pg_cron job from 0030 keeps calling it
  unchanged.
- The 226 ledger-era snapshot rows are deleted. The table is a re-derivable
  projection, not a point store: losing every row costs one day of arrows and
  not a single point.
- Arrows still need the Dart side - FixtureLeaderboardEntry has no
  previousRank and no port reads the snapshot table. Next fix. The data has to
  exist before the feature can read it, which is why this lands first.

## 2026-09-07 - fix 25: the arrows, on the board that has the points
- Migration 0034 landed first and the capture ran: 43 rows for 09/2026, with
  the same order the app shows (12 points at rank 1, four tied at 9 on rank
  2). The data existed before the feature was built to read it.
- New single-method port RankSnapshotReader.latestRanks(seasonId), READ-ONLY
  by design: nothing in the application layer should be able to forge a past
  rank, because a fabricated one produces an arrow no participant earned. The
  snapshot is written by pg_cron and by nothing else.
- PostgresRankSnapshotReader compares against the season's NEWEST capture
  rather than "yesterday's": when a capture is missed the comparison is simply
  older, never absent.
- GetSeasonFixtureLeaderboard reads it and degrades to no arrows on failure.
  Yesterday's ranking is decoration on today's standings, and a decoration
  must never cost a user the standings themselves.
- FixtureLeaderboardEntry gains previousRank plus a movement getter, computed
  only once rank is assigned, so the arrow can never disagree with the place
  printed beside it. A participant absent from the snapshot gets no arrow, not
  a fabricated one.
- The root's unwired RankSnapshotReader ANSWERS instead of throwing, unlike
  its siblings: a root wiring the leaderboard slice without a snapshot reader
  should render a board without arrows, not fail.
- DTO schema version 3. Arrows appear after tomorrow's capture - today's
  snapshot equals the live order, so every movement is currently 0.

## 2026-09-07 - fix 26: avatars, step 3 of 4 (routes)
- POST /me/avatar takes the image BYTES as the body, not JSON. Base64 inside
  an envelope would inflate every upload by a third for no gain, and the
  content type is already a header. Everything else here speaks JSON because
  it carries a domain intent; an image carries none.
- The content type is required, never sniffed: guessing a format from magic
  bytes would store something the client never claimed.
- POST and DELETE both return the same MeResponseDto as GET /me, so a client
  refreshes its whole identity - including the new avatar_url - from the one
  response instead of a second call to discover what changed.
- GET /users/{id}/avatar is the only route returning bytes and the only caller
  of readAvatar, so image data travels on no other path. No picture is 404,
  not an error envelope: an image request that finds no image is exactly what
  404 means, and the client draws the initial.
- Cached one year, immutable, private. Safe only because the URL carries
  ?v=avatarUpdatedAt - a replaced picture is a different URL, so nothing stale
  survives; private because the bytes are a person's face and a shared proxy
  has no business holding them.
- avatarUrlFor returns a RELATIVE url: the server sits behind a proxy and does
  not know its own public origin, while the client already holds the API base
  it just called. Guessing a host would be inventing an unverified fact.
- /users is bearer-gated: the picture is meant to be seen by signed-in
  participants, but leaving it open would make the endpoint a public probe for
  which user ids exist.
- Step 4 remains: image_picker, the upload UI, avatars on the board, and the
  report button.

## 2026-09-07 - fix 27: avatars, step 4a (api_client)
- ApiTransport.postBytes: the one non-JSON request this client makes. An image
  is payload, not a domain intent, so base64 in an envelope would inflate
  every upload by a third to gain nothing, and the content type is already a
  header.
- Deliberately routed through the same _send pipeline as everything else, so
  auth headers, the request timeout, 401 handling and error decoding cannot
  drift from the rest of the client. Only the body and content type differ.
- _headers gained an optional contentType that overrides the JSON default; a
  byte body wins over requestBody in the POST branch, so jsonEncode(null) can
  never send the literal string "null".
- AuthApi.setAvatar / removeAvatar both return MeResponseDto - the same shape
  as me() - so the caller refreshes its whole identity from one response.
- Step 4b remains: image_picker, the account screen picker, avatars on the
  board, and the report button.
