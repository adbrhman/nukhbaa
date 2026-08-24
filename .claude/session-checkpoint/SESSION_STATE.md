# SESSION STATE — Phase 7 (production readiness + ELITE OBSIDIAN)

**آخر تحديث:** 2026-08-25.

## ما تم إنجازه فعليًا ومدفوعًا
- Phase 6 (FixtureLeaderboard): كامل، backend (5ada79e) + mobile (e76b75d).
- Checkpoint system نفسه: مُنشأ (e49be2d).
- ELITE OBSIDIAN theme (dark + light): app_colors.dart + app_colors_light.dart
  محدَّثان بقيم النظام الجديد. تعديل قيم فقط، لا تغيير بنيوي — كل الشاشات
  تقرأ عبر AppColors/AppTokens فلا حاجة لتعديل أي شاشة لهذه الدفعة.
  flutter analyze نظيف بعد dark. flutter test الكامل + analyze النهائي
  بعد إضافة light: **تحقق من نتيجته الفعلية في بداية الجلسة القادمة —
  لم يُؤكَّد بعد داخل هذه الجلسة.**
- Commit المتوقع لهذه الدفعة: "chore(theme): apply ELITE OBSIDIAN palette"
  — تحقق فعليًا عبر git log أنه تم فعلاً قبل افتراض ذلك.

## القرار المعماري النهائي (Phase 7)
Fixture/FixturePrediction = المصدر الوحيد لدورة حياة التنبؤ/التسجيل/القفل/
Ledger/Reactions/Notifications. Round يتحول لمفهوم تنظيمي فقط (matchday/
تجميع/فلترة/admin) — لا يُحذف قبل إثبات صفر استخدام فعلي، ملفًا ملفًا.

## Phase 7.1 (تحليل) — النتيجة الحاسمة
Backend لـ FixturePrediction **مكتمل 100%**: migrations 0019/0020، route
`apps/server/routes/seasons/[id]/fixtures/[fixtureId]/prediction/index.dart`
(body: home_goals/away_goals/is_double → FixturePredictionView)،
composition_root مربوط (submitFixturePrediction/scoreFixture)، DTOs جاهزة
(FixturePredictionDto, FixturePredictionCommandDto, ParticipantFixtureScoreDto,
FixtureScoresDto — كل الحقول موثقة في هذا الملف).

**الفجوة الكاملة محصورة في:**
- packages/api_client/lib/src/prediction_api.dart — صفر methods لـ fixture
  prediction (فقط Round-based: submitPrediction/getMyPrediction/
  listRoundPredictions/myPredictions).
- apps/mobile/lib/features — لا يوجد مجلد fixture_prediction إطلاقًا.

## سلسلة التنقل الحية المؤكدة (لا تُكسر)
competition_seasons_screen → SeasonRoundsScreen → RoundFixturesScreen →
PredictionScreen (Round-based بالكامل، 562+634 سطر).
matches_feed_screen.dart (386 سطر) يعرض RoundFixtureCardDto من
GET /feed/matches — أقرب نقطة دخول طبيعية لإضافة زر "توقّع" الجديد لاحقًا.

## بنية الثيم الحالية (مرجع لأي عمل UI قادم)
كل شيء مركزي وسليم: AppColors/AppColorsLight (قيم فقط) → AppTokens
(ThemeExtension، dark/light) → AppTheme._build (يبني ThemeData كاملاً) →
ThemeController (Riverpod Notifier + SecureStorage). AppRadius وAppTypography
منفصلان (font الحالي: IBMPlexSansArabic — Tajawal لم يُستبدل بعد، لم يُطلب
صراحة كأولوية). Color(0xFF..) مباشر خارج theme/design: ملفان فقط
(team_branding.dart, match_card.dart) — نطاق استبدال صغير لاحقًا.

## الخطوة التالية الفورية (ابدأ هنا في الجلسة القادمة)
1. تحقق من نتيجة flutter analyze/test بعد app_colors_light.dart (لم تُؤكَّد).
2. إن نجحت: تأكد أن commit "ELITE OBSIDIAN palette" و push تم فعلاً
   (git log --oneline -5).
3. انتقل لبقية 7.2: تصميم api_client method (submitFixturePrediction) على
   نمط prediction_api.dart الحالي، ثم شاشة FixturePrediction في mobile
   (استخدم matches_feed كنقطة انطلاق للتصفح، أضف زر توقّع).
4. طبّق ELITE OBSIDIAN على الشاشة الجديدة مباشرة بما أنها جديدة بالكامل
   (لا حاجة لإعادة تصميم شاشة قديمة أولاً).
5. لا تلمس Round/RoundFixture بالحذف حتى اكتمال 7.2-7.6.

## أين المشروع
الجذر: /home/dev/nukhbaa-backup-1787537565 (GitHub adbrhman/nukhbaa, main).
proot-distro login ubuntu ثم su - dev.
