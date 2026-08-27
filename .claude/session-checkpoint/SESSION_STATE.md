# نقطة توقف — بعد 7.4.8 (نجاح كامل)، 7.5 معلّقة (NOT REPRODUCED)

## آخر commit مدفوع
`ed6c9dc` (origin/main، HEAD)

## الحالة المؤكَّدة
- **7.4 (كامل، 7.4.1→7.4.8)** ✅ — Season-based Fixture Administration منجزة بالكامل.
  commits: 25ca325 (7.4.3+7.4.4), eef4f8d (7.4.5), 8fa6d9b (7.4.6), 6852278+09c7efd (7.4.7).
  7.4.8 Full Verification نُفِّذت ونجحت بالكامل: format-check✅ analyze✅ import-lint✅ test(8 حزم)✅ test-mobile 107/107✅.
- **7.5 — score_fixture doubling bug: NOT REPRODUCED / NOT CONFIRMED.**
  تحقيق كامل عبر git log/show لكل كوميت يذكر "doubl" في كامل تاريخ الريبو + كامل تاريخ score_fixture.dart وscoring.dart منذ إنشائهما (949ed69) — لم يُعثر على أي reproduction، test فاشل تاريخيًا، أو تشخيص موثّق يربط doubling بمنطق ScoreFixture تحديدًا. البند غير مغلق كـfixed ولا كـwontfix — معلَّق بانتظار reproduction فعلي جديد إن ظهر. **لم يُلمس أي كود متعلق بـScoreFixture.**
- **ملاحظة معمارية مستقلة (ليست 7.5، لا تُخلط بأي مرحلة حالية):**
  PUT /fixtures/{id}/result يشغّل تلقائيًا Round-path (ScoreRound→ledger.point_entries) بينما POST /fixtures/{id}/score هو Fixture-path يدوي منفصل (ScoreFixture→ledger.fixture_point_entries). لفكستشر مرتبطة بـRound وSeason معًا، هذا خطر ازدواج ائتمان معماري كامن (لا استعلام حالي يجمع الاثنين فعليًا). تحتاج معالجة لاحقًا ضمن انتقال النظام لـSeason/Fixture — بلا إصلاح مقترح بعد.

## الترتيب الرسمي المعتمد (لم يتغيّر)
7.4 ✅ → **7.5 (معلّقة، غير مؤكدة)** → 7.6 notification test → 7.7 FixturePredictionScreen → 7.8 ✅(سابقًا) → 7.9 ✅(سابقًا) → 7.10 (جزئي) → 7.11 → 7.12

## تعارض تسمية مهم
track منفصل من commits (8b5ad4c, 681f604, 64cbda5, e0e5ca3, c0120f1, ed6c9dc) نُفِّذ باسم "7.7" خطأً (current-season endpoint، منجز ومدفوع). 7.7 الرسمية = FixturePredictionScreen، لم تبدأ بعد.

## القرار المعماري المثبَّت (النظام المستهدف)
Monthly Competition → Season → Fixtures → Predictions → Daily Doubles → Results & Scoring → Leaderboards
ممنوع: مسار مسابقات متعددة للمستخدم العادي، items.first لتحديد "الحالية"، إعادة CompetitionListScreen القديمة. يسري على كل مرحلة قادمة وعلى Admin Panel المستقبلية.

## Comprehensive Admin Panel — Phase مستقلة بعد 7.12 فقط (لا تُبنى الآن، ولا تُخلط بـ7.5/7.6/7.7)
Dashboard, Monthly Competitions, Fixtures, Predictions, Daily Doubles, Results & Scoring, Leaderboards, Users, Competitions, Teams, Social, Notifications, Reports & Analytics, Audit Logs, System Health, Roles & Permissions, Settings.

## دروس منهجية متراكمة
1. flutter pub run build_runner build وليس dart run build_runner build.
2. بعد حذف من ARB: flutter gen-l10n ثم build_runner فورًا.
3. قبل حذف أي دالة/كلاس يبدو Legacy: grep بالاسم الفعلي الدقيق.
4. ملفات *.g.dart مستثناة من git، طبيعي.
5. heredoc إلزامي للصق متعدد الأسطر في Termux؛ تحقّق فورًا بـ ls -la + wc -l + md5sum.
6. الريبو الحقيقي: ~/nukhbaa-backup-1787537565 فقط.
7. الملفات المنزَّلة من المتصفح على Termux تصل إلى /sdcard/Download/، تحقّق بـmd5sum عند التكرار.
8. Response.json(body: null) في dart_frog ينتج نصًا فارغًا لا 'null' الحرفية.
9. melos run verify هو المرجع الرسمي المطابق لـCI حرفيًا.
10. لا تفترض حالة الكود من zip قديم — تحقّق دائمًا عبر أوامر حية على الجهاز أولًا.
