# تحكيم الواجهة -- أكتوبر 2026 (المرحلة الأولى: قياس بلا إصلاح)

المرجع: `docs/project-context.md`. البروتوكول: `docs/agent-script-protocol.md`.
الأساس: `main` عند `78843b4` (مطابق للنسخة المرفوعة في 2026-10-03)، ولقطات الشاشات
الخمس في الوضعين النهاري والليلي من الجهاز في اليوم نفسه.
النطاق: تطبيق الجوال، والويب (البناء نفسه من `apps/mobile`)، ولوحة المشرف.
معيار الحكم: WCAG 2.2 AA (قرار 2026-09-24) وإرشادات Material لأهداف اللمس (48dp).

---

## 1. الخلاصة

| الخطورة | العدد | المعنى |
|---|---:|---|
| حرج | 2 | يمسّ الفعل الأساسي في التطبيق أو يرسب في AA بفارق كبير |
| عالٍ | 11 | رسوب AA أو هدف لمس صغير في شاشة رئيسية |
| متوسط | 13 | اتساق بصري، تكبير الخط، RTL، الويب |
| منخفض | 7 | تنظيف ودَين تصميمي |
| **المجموع** | **33** | |

أهم خمسة:
1. **UI-01** أزرار `+`/`−` في بطاقة المباراة ارتفاع لمسها 26px (المطلوب 48) -- هي فعل التطبيق الأول.
2. **UI-02** شارة «أمس/اليوم/غداً» في الوضع الفاتح **2.86:1** بخط 9px (ظاهرة في لقطتك).
3. **UI-06** شارة «نجاح» زرقاء لا خضراء، ونصّها 3.61:1 فاتحًا و4.35:1 داكنًا؛ وشارة «خطأ» دون 4.5 في الوضعين.
4. **UI-08** خلفية بطاقة المباراة الداكنة `#2F2F2F` مكتوبة يدويًا من اللوحة الرمادية الملغاة، وعليها «مباشر» بالأحمر 3.82:1 وزر «توقعات الجميع» بالأزرق 2.95:1.
5. **UI-03 / UI-04** الشريط السفلي: التبويب النشط في الفاتح 4.49:1، ارتفاع ثابت 70 بخط 10px، شفافية 0.96 تُظهر ما تحته (اسم «Ahmed Alyateem» مقروء خلف الشريط في لقطة المتصدرين)، ولا يُعلن قارئ الشاشة أيّ تبويب مختار.

ما هو جيد ويجب ألا يُكسر: سقف تكبير الخط 2.0 مع اختبارات انحدار (`text_scale_regression_test`)،
احترام «إزالة الحركات» في الهيكل العظمي ونقطة «مباشر»، رمز `primaryText` للأزرق كنص،
اختبار تباين الزر المملوء، `lang="ar" dir="rtl"` في صفحة الويب، دمج البطاقات دلاليًا
(`MergeSemantics`)، وعزل الأرقام اللاتينية داخل الجمل العربية في لوحة المشرف.

---

## 2. المنهج وحدوده

- **الشجرة الفعلية** لا الذاكرة: كل ملف وسطر في هذا التقرير مأخوذ من `78843b4`.
- **التباين** محسوب بصيغة WCAG نفسها التي يستعملها `Color.computeLuminance` من قيم
  `AppColors` و`AppColorsLight` كما هي، مع دمج الشفافية كما يدمجها `Color.alphaBlend`.
  كل رقم في القسم 4 مثبّت في اختبار (القسم 8).
- **الشاشات** قُرئت كودًا وقورنت باللقطات.
- **القياس على الجهاز**: لم أستطع تشغيل Flutter في بيئتي (الوصول إلى
  `storage.googleapis.com` و`pub.dev` محجوب بسياسة الشبكة)، فبنيتُ اختبار المسح
  ليقيس على جهازك عند أول تشغيل للسكربت، ويكتب كل ما وجده في
  `docs/reviews/ui-audit-2026-10-measured.md` (يُولَّد ويُضاف إلى الـ commit نفسه).
  ما يجده المسح ولم يرد هنا يُضاف إلى هذا التقرير قبل الإصلاح.
- حدود أدوات Flutter نفسها:
  - `textContrastGuideline` لا يرى البطاقة المدموجة دلاليًا (تسمية واحدة مجمّعة لا
    تطابق أي `Text`)، فبطاقات الرئيسية وتوقعاتي وصفوف الجدول مقيسة بأزواج الرموز بدلًا منه.
  - النص الذي يصغّره `FittedBox` لا يفيض أبدًا، فاختبار الفيضان لا يراه (UI-17).
  - هدف اللمس الملاصق لحافة الشاشة يُتخطّى (الشريط السفلي مثلًا)، فله اختبار مركّز.

---

## 3. حصر الشاشات (من الشجرة الفعلية)

| القسم | الشاشة/المكوّن | الملف | يصلها المسح |
|---|---|---|---|
| الدخول | تسجيل الدخول | `features/auth/sign_in_screen.dart` | `sign-in` |
| الدخول | إعادة كلمة المرور (ويب) | `features/auth/password_reset_screen.dart` | لا |
| الدخول | اختيار الاسم / القواعد / قفل البصمة | `name_setup_screen.dart`, `rules_screen.dart`, `app_lock.dart` | لا |
| الهيكل | الشريط السفلي | `features/auth/nukhbaa_shell.dart` | `bottom-nav`, `shell.*` |
| تبويب 1 | الرئيسية + تحدي اليوم | `features/auth/home_screen.dart`, `gamification/daily_challenge_card.dart` | `home.data`, `shell.home` |
| تبويب 2 | المباريات: شريط الأيام، البطاقة، «مباشر»، التقويم، توقعات الجميع | `fixture_prediction/current_month_fixtures_screen.dart`, `widgets/*` | `matches.open`, `matches.live`, `shell.matches` |
| تبويب 3 | توقعاتي + مشاركة الإصابة | `history/prediction_history_screen.dart`, `history/exact_hit_share.dart` | `predictions.data`, `shell.predictions` |
| تبويب 4 | المتصدرون: الشهر/اليوم/الموسم، المنصة، الجدول، البطل | `leaderboards/leaderboards_screen.dart`, `widgets/*` | `leaderboards.month`, `board.widget`, `shell.leaderboards` |
| تبويب 5 | الحساب + الإعدادات | `auth/account_screen.dart`, `auth/account_settings_screen.dart` | `shell.account` |
| ثانوي | الإشعارات، إعداداتها، الفرق المفضلة | `notifications/*` | `shell.notifications` |
| ثانوي | نقاطي، مواسمي، سجل الموسم، بطاقة النخبة | `record/*` | لا |
| ثانوي | شاراتي، تعلّم من توقعاتك، ادعُ أصدقاءك | `gamification/*` | لا |
| ثانوي | سجل الأبطال، ترتيب موسم، المجموعات، السجل | `leaderboards/champions_record_screen.dart`, `groups/*`, `ledger/*` | لا |
| المشرف | المحور + 16 قسمًا (`AdminSection`) | `features/admin/**` | `admin.phone`, `admin.desktop` |
| الويب | صفحة الدخول والـ manifest | `apps/mobile/web/index.html`, `web/manifest.json` | اختبار UI-24 |

الشاشات المكتوب عليها «لا» تُضاف إلى المسح مع دفعة الإصلاح التي تلمسها.

---

## 4. مصفوفة التباين من الرموز

نص على خلفية (AA: 4.5 للنص العادي، 3 للنص الكبير وحدود عناصر التحكم). **الغامق راسب**.

### الداكن

| النص \ الخلفية | background | backgroundElevated | surface | surfaceElevated | surfaceHigh |
|---|---:|---:|---:|---:|---:|
| textPrimary | 18.47 | 21.00 | 17.26 | 15.42 | 13.48 |
| textSecondary | 13.99 | 15.91 | 13.07 | 11.68 | 10.21 |
| textMuted | 8.88 | 10.10 | 8.30 | 7.42 | 6.48 |
| primaryText | 8.11 | 9.22 | 7.58 | 6.77 | 5.92 |
| primaryLight | 5.40 | 6.14 | 5.04 | 4.51 | **3.94** |
| primary (كنص) | **4.06** | 4.62 | **3.80** | **3.39** | **2.97** |
| error | 5.26 | 5.98 | 4.92 | **4.39** | **3.84** |
| bronze | 5.47 | 6.22 | 5.11 | 4.57 | **3.99** |
| gold / silver / success | ≥8 | ≥8 | ≥8 | ≥8 | ≥8 |

على التعبئات: أبيض على `primary` 4.54، أبيض على `primaryLight` **3.42**، أبيض على `error` **3.51**.
حدود: `border` على `surface` 1.39 (زخرفي، مقبول)، `surface` مقابل `background` 1.07.

### الفاتح

| النص \ الخلفية | background | surface | surfaceElevated | surfaceHigh | successContainer |
|---|---:|---:|---:|---:|---:|
| textPrimary | 17.24 | 18.52 | 16.47 | 14.85 | 16.71 |
| textSecondary | 8.12 | 8.73 | 7.76 | 7.00 | 7.87 |
| textMuted | 5.59 | 6.01 | 5.34 | 4.82 | 5.42 |
| primary | 6.24 | 6.70 | 5.96 | 5.37 | 6.05 |
| primaryLight | **4.19** | **4.50-** | **4.00** | **3.61** | **4.06** |
| success | **4.24** | 4.55 | **4.05** | **3.65** | **4.11** |
| silver | **4.43** | 4.76 | **4.23** | **3.82** | **4.29** |
| error | 5.02 | 5.39 | 4.79 | **4.32** | 4.87 |

على التعبئات: نص داكن على `gold` الفاتح **2.93**، أبيض على `gold` 6.32، أبيض على `primaryLight` **4.4988**.
حدود: `border` الفاتح 3.46 (أثقل بمرتين ونصف من الداكن 1.49 -- انظر UI-19).

### الأزواج المستعملة فعلًا والراسبة

| الزوج | المكان | داكن | فاتح | البند |
|---|---|---:|---:|---|
| شارة اليوم: `onBronze` ثابت على `gold` | `fixtures_date_bar.dart:231-241` | 11.08 | **2.86** | UI-02 |
| تاريخ اليوم المختار: أبيض 85% على `primary` | `fixtures_date_bar.dart:193-194` | **3.73** | 5.30 | UI-02 |
| التبويب النشط: `primaryLight` على الشريط | `nukhbaa_shell.dart:283` | 6.11 | **4.49** | UI-03 |
| عدّاد الإشعارات: أبيض على `error` | `home_screen.dart:479` | **3.51** | 5.39 | UI-05 |
| شارة نجاح: `primaryLight` على غسلة زرقاء | `app_badge.dart:33-36` | **4.35** | **3.61** | UI-06 |
| شارة خطأ: `error` على غسلته | `app_badge.dart:37-40` | **4.37** | **4.28** | UI-06 |
| «لوحة النخبة»: أبيض على بداية التدرّج | `home_screen.dart:529`, `app_colors.dart:130` | **3.42** | **4.50-** | UI-07 |
| «مباشر» والدقيقة: `error` على البطاقة | `fotmob_match_card.dart:1208,1230` | **3.82** | 5.39 | UI-08 |
| «توقعات الجميع»: `primary` كنص على البطاقة | `fotmob_match_card.dart:1556` | **2.95** | 6.70 | UI-08 |
| رتبة الفضة على غسلتها | `leaderboard_board.dart:589` | 7.21 | **3.90** | UI-13 |
| رتبة البرونز على غسلتها | `leaderboard_board.dart:589` | **4.19** | **4.22** | UI-13 |
| صعود على صفّ اللاعب نفسه | `leaderboard_board.dart:848` | 9.03 | **3.66** | UI-13 |
| هبوط على صفّ اللاعب نفسه | `leaderboard_board.dart:848` | **4.24** | **4.33** | UI-13 |
| حدّ حقل المشرف على تعبئته (3:1) | `admin_ui_kit.dart:98-106` | **1.24** | 3.43 | UI-22 |

---

## 5. النتائج

الأعمدة: الشاشة، الخطورة، الدليل، الملف:السطر (تحت `apps/mobile/lib/` ما لم يُذكر غيره)، الإصلاح المقترح.

### حرج

| # | الشاشة | الدليل | الملف:السطر | الإصلاح المقترح |
|---|---|---|---|---|
| UI-01 | المباريات -- بطاقة المباراة | منطقتا `+`/`−` بحجم 61×26 (Android: 48). الإصبع يضغط الرقم أو الزر الآخر؛ هذا أكثر لمس في التطبيق كله. | `features/fixture_prediction/widgets/fotmob_match_card.dart:1311-1313`, `:1415` | تبقى البطاقة بتصميمها (قرار 2026-09-24 يسمح بتغيير الأحجام الداخلية): منطقة لمس 48 لكل زر مع بقاء الرسم 26 عبر توسيع مساحة الضغط خارج الصندوق رأسيًا، أو صندوق 61×100 بمنطقتين 37. |
| UI-02 | المباريات -- شريط الأيام | فاتح: «أمس/اليوم/غداً» نص داكن ثابت `AppColors.onBronze` على ذهبي فاتح `#755D00` = **2.86:1** بخط **9px** (لقطتك). داكن: سطر التاريخ في اليوم المختار أبيض 85% = **3.73:1** بخط 10px. | `features/fixture_prediction/widgets/fixtures_date_bar.dart:231`, `:238`, `:241`, `:193-194` | رمز جديد `onGold` في `AppTokens` (داكن `#2A1E04` = 10.0، فاتح أبيض = 6.32) بدل لون الداكن الثابت؛ الشارة 10px على الأقل؛ سطر التاريخ `onPrimary` كاملًا. |

### عالٍ

| # | الشاشة | الدليل | الملف:السطر | الإصلاح المقترح |
|---|---|---|---|---|
| UI-03 | الشريط السفلي (فاتح) | التبويب النشط `#2F6BFF` على الأبيض = **4.4988:1**، الرقم نفسه الذي أُصلح في الداكن سابقًا. | `features/auth/nukhbaa_shell.dart:283` | `tokens.primaryText` (فاتح 6.70، داكن 9.22). |
| UI-04 | الشريط السفلي | ارتفاع ثابت 70 وتسمية **10px**؛ لا `Semantics(selected)` فقارئ الشاشة لا يعرف التبويب الحالي؛ خلفية بشفافية 0.96 مع `extendBody` تُظهر المحتوى خلفها (لقطة المتصدرين: «Ahmed Alyateem» و«12» تحت الشريط)؛ التسميات عربية مكتوبة يدويًا. | `features/auth/nukhbaa_shell.dart:219`, `:223`, `:230-276`, `:285`, `:297` | خلفية معتمة + خط علوي `border`؛ تسمية `labelMedium` (12)؛ ارتفاع أدنى 64 يكبر مع الخط؛ `Semantics(button, selected)`؛ التسميات من `AppLocalizations`. |
| UI-05 | الرئيسية + الحساب -- جرس الإشعارات | أبيض على `#FF3B4D` = **3.51:1** (داكن)؛ «19» بعرض رقمين تغطي الجرس كله تقريبًا (اللقطات). | `features/auth/home_screen.dart:479-481`, `features/auth/account_screen.dart:80`, `:200` | تعبئة شارة ثابتة `#D11A2B` (أبيض 5.39) في الوضعين عبر `badgeTheme`؛ «9+» فوق التسعة؛ إزاحة الشارة إلى زاوية الأيقونة. |
| UI-06 | توقعاتي، البطاقة بعد النتيجة، كل `AppBadge` | لون «نجاح» **أزرق** (`primaryLight` على غسلة زرقاء) خلافًا لنظام الألوان الدلالي (أخضر = نجاح، قرار 2026-09-24)، وتباينه 4.35 / **3.61**؛ «خطأ» 4.37 / 4.28. | `core/ui/app_badge.dart:33-40` | نجاح: `successContainer` + نص `success` (داكن 9.49)، ورمز نص أخضر للفاتح `#00754E` (5.19 على حاويته، 5.75 على الأبيض). خطأ: نص `errorText` داكن `#FF7A85` (7.11 على حاويته)، والفاتح كما هو على `errorContainer` (4.73). |
| UI-07 | الرئيسية -- «لوحة النخبة» | النص الأبيض (عنوان 16px w800 وسطر 13px بشفافية 0.9) على تدرّج يبدأ بـ `#008BFF`: **3.42** داكن، و3.04 لسطر الـ0.9. العيب في الرمز نفسه `primaryGradient = [primaryLight, primary]`. | `features/auth/home_screen.dart:529`, `:575`; `core/theme/app_colors.dart:127-131`; `core/design/app_colors_light.dart:70-74` | تدرّج النص الأبيض `primary → primaryDark` (أبيض 4.54 → 6.70 داكنًا، 6.70 → 10.36 فاتحًا) كما فعل زر المضاعفة؛ وإبقاء التدرّج الحالي للزخرفة فقط (الشعار). |
| UI-08 | المباريات -- بطاقة المباراة (داكن) | الأساس `Color(0xFF2F2F2F)` من اللوحة الرمادية التي ألغتها `app_colors.dart` صراحةً؛ البطاقات رمادية على صفحة كحلية. عليها «مباشر»/الدقيقة بالأحمر **3.82** (11px)، وزر «توقعات الجميع» بالأزرق **2.95** (12px). | `features/fixture_prediction/widgets/fotmob_match_card.dart:477-479`, `:1208`, `:1230`, `:1545`, `:1556` | الأساس `tokens.surface` (لا تغيير في التخطيط)؛ نص الزر `primaryText` (5.88 على الرمادي، 7.58 على surface)؛ نص الأحمر `errorText`. |
| UI-10 | الرئيسية، المباريات (فاتح) | أعلام بحقل أبيض تختفي على البطاقة البيضاء: فنلندا صليب أزرق عائم، إنجلترا صليب أحمر بلا علم (اللقطات). الشعار المرفق يُرسم بلا حدّ. | `core/ui/team_logo.dart:91-104` | حدّ رفيع `border` حول الشعار المرفق في الفاتح (أو صفيحة `surfaceElevated` خلفه). |
| UI-13 | المتصدرون -- المنصة والجدول | رتبة الفضة فاتحًا **3.90**، البرونز **4.19/4.22** (11px)؛ أسهم الحركة على صفّ اللاعب نفسه: صعود فاتح **3.66**، هبوط **4.24/4.33**. | `features/leaderboards/widgets/leaderboard_board.dart:578-600`, `:848` | نص الرتبة `textPrimary` على غسلة الميدالية (الميدالية في الحلقة لا في النص)، أو رموز نص للميداليات: فضة فاتحة `#56657A` (4.75)، برونز داكن `#D08A55` (4.85)؛ الحركة بـ `successText`/`errorText`. |
| UI-15 | المتصدرون، توقعاتي -- أزرار الأقسام | `SegmentedPills` ارتفاعها 42. | `core/ui/segmented_pills.dart:41` | 48 (لا يتغيّر الشكل إلا 6px). |
| UI-16 | المباريات | شريحة «مباشر» 32، زر «ضاعِف النقاط» و«توقعات الجميع» 36. | `features/fixture_prediction/widgets/live_matches_chip.dart:115`; `fotmob_match_card.dart:1588`, `:1531` | يبقى الرسم 36/32، ومساحة الضغط 48 (`SizedBox` شفاف حوله). |
| UI-22 | لوحة المشرف -- كل الحقول | `AdminTextField` يستبدل حدّ الحقل في الثيم بـ `border` (داكن **1.24:1** على تعبئته) فتكاد الحقول لا تُرى؛ الثيم العام أصلح هذا في `app_theme.dart:86-93` لكن العُدّة تتجاوزه. | `features/admin/widgets/admin_ui_kit.dart:98-106` | حذف `border/enabledBorder` من العُدّة ليرث الحقل `inputDecorationTheme`. |

### متوسط

| # | الشاشة | الدليل | الملف:السطر | الإصلاح المقترح |
|---|---|---|---|---|
| UI-09 | المباريات | غسلة لون الفريق 18% على حافتي كل بطاقة تجعل لكل بطاقة لونًا (زيتي، بني، بنفسجي في لقطتك) -- يخالف «نظام ألوان دلالي واحد، لا لون مختلف لكل بطاقة» (2026-09-24). | `fotmob_match_card.dart:480-482` | **قرار منك**: إبقاء الهالة حول الشعار فقط، أو خفض الغسلة إلى 6%. |
| UI-11 | المتصدرون، الحساب | الحرف الأول للاسم: «المستشار» و«ابو الياس» تظهر «ا» وحدها، فتبدو خطًّا عموديًا «I» (لقطة المنصة). وفي شعارات الفرق الاحتياطية النص `textPrimary` فوق لون الفريق أيًّا كان (أبيض على أصفر دورتموند ~1.3:1). | `core/ui/user_avatar.dart:64-67`; `core/ui/team_logo.dart:139-155` | تخطّي «ال» وكلمة «أبو/ابو»؛ ولون الحرف بحسب إضاءة الخلفية (`computeLuminance`). |
| UI-12 | المتصدرون -- المنصة | ثلاثة متعادلون على المركز 1 بارتفاعات 172/144/136 توحي بأول وثانٍ وثالث (لقطتك). | `leaderboard_board.dart:383-418` | ارتفاع واحد للمتعادلين. |
| UI-14 | المتصدرون -- شريط الفترة | أيقونة التقويم تظهر كزر في «الشهر» و«الموسم» ولا تفعل شيئًا (اللمس فعّال في «اليوم» وحده). | `features/leaderboards/leaderboards_screen.dart:477`, `:551-563` | إظهار الأيقونة والسهم في «اليوم» وحده. |
| UI-17 | المباريات، المتصدرون، الرئيسية | `FittedBox(scaleDown)` يُبقي النص بحجمه مهما كبّر المستخدم الخط (WCAG 1.4.4)؛ اختبارات الفيضان تمرّ لأن النص يصغر: شريط الأيام (ارتفاع ثابت 70)، نسب الفوز، عناوين الجدول، الحركة، شارة المواسم. | `fixtures_date_bar.dart:52`, `:219`; `fotmob_match_card.dart:1448`; `leaderboard_board.dart:626`, `:852`; `home_screen.dart:453`, `:558` | ارتفاع يتبع المحتوى (حدّ أدنى 58) والسماح بسطرين؛ `FittedBox` للشعار اللاتيني وحده. |
| UI-18 | المباريات | زر المضاعفة في خانة ثابتة 130px فيُقصّ «ضاعِف…» عند 1.3 و2.0؛ أسماء الفرق سطر واحد مقصوص («مقدونيا الشمالية»). | `fotmob_match_card.dart:624-653`, `:917-924` | خانة مرنة ونص بسطرين عند التكبير. |
| UI-19 | كل الشاشات (فاتح) | حدّ البطاقات `#0A1420` بشفافية 50% = 3.46:1 مقابل 1.49 في الداكن؛ كل بطاقة وزر مؤطّر بخط رمادي ثقيل (لقطات الفاتح كلها). | `core/design/app_colors_light.dart:63` | حدّ زخرفي `#D3DCE7` (1.39 مثل الداكن)، ويبقى `controlBorder` (5.59) لحدود عناصر التحكم. |
| UI-20 | التبويبات الخمسة | ثلاثة أنماط رأس: الرئيسية شعار داخل الصفحة بلا AppBar، المباريات AppBar كحلي 44 بالشعار، توقعاتي AppBar أسود بعنوان، المتصدرون عنوان كبير داخل الصفحة، الحساب AppBar أسود «نُخبة». | `home_screen.dart:53`; `current_month_fixtures_screen.dart:275-283`; `prediction_history_screen.dart:66`; `leaderboards_screen.dart:202-210`; `account_screen.dart:72` | **قرار منك**: رأس واحد `AppTabHeader` (عنوان التبويب + إجراءاته) بلون الصفحة نفسه. |
| UI-24 | الويب | `maximum-scale=1.0, user-scalable=no` يمنع تكبير الصفحة بالإصبعين (WCAG 1.4.4، ويرسب في Lighthouse)؛ لون الـ manifest `#0d1b2a` غير لون التطبيق `#071426`. | `apps/mobile/web/index.html:9`; `apps/mobile/web/manifest.json:6-7` | حذف القيدين؛ توحيد الألوان على `#071426`. |
| UI-25 | الويب | أزرار مبنية بـ `GestureDetector` (المضاعفة، توقعات الجميع، «مباشر») لا يصلها مفتاح Tab ولا يظهر عليها مؤشر اليد. | `fotmob_match_card.dart:1523`, `:1602`; `live_matches_chip.dart:109` | `InkWell` (يركّز ويعرض المؤشر) أو `FocusableActionDetector` + `MouseRegion`. |
| UI-26 | المباريات | علامة «تم الحفظ» بين العدّادين زرقاء بأيقونة `Colors.white`، والقرار: الأخضر = توقع محفوظ. | `fotmob_match_card.dart:1070-1083` | `success` + `onSuccess`. |
| UI-27 | الرئيسية | زرّا الجرس والحساب بلا `tooltip`: زر الحساب بلا اسم لقارئ الشاشة، والجرس يُقرأ «19» فقط. | `features/auth/home_screen.dart:472-492` | `tooltip: l10n.notifications` واسم للحساب. |
| UI-32 | كل الشاشات (فاتح) | «الذهبي» الفاتح `#755D00` يُقرأ زيتونيًا/بنيًا (حلقة المنصة، شارة «أمس») ففقد معنى الإنجاز. | `core/design/app_colors_light.dart:34` | **قرار منك**: ذهبي زخرفي للحلقات `#A87B00` (3.82 مقابل الأبيض، يكفي للعناصر غير النصية) ورمز نص منفصل للذهبي. |

### منخفض

| # | الشاشة | الدليل | الملف:السطر | الإصلاح المقترح |
|---|---|---|---|---|
| UI-21 | توقعاتي | الأقسام ملتصقة بالـ AppBar (حشوة علوية 4)؛ خط فاصل بين بطاقات لها إطار أصلًا (فاصل مزدوج في اللقطة). | `features/history/prediction_history_screen.dart:77-82`; `features/competition/widgets/async_list_view.dart:125` | حشوة `md`؛ فاصل بمسافة `sm` بدل `Divider` في قوائم البطاقات. |
| UI-23 | لوحة المشرف | `Colors.white` ثابت في ثلاثة أماكن؛ بانر النجاح أزرق؛ عُدّة كاملة (`AdminCard`، `AdminPrimaryButton`...) موازية لـ `core/ui` بأنصاف أقطار رقمية 12/16؛ تعليق «TEMP DIAGNOSTIC» في كود الإنتاج. | `user_sanction_section.dart:458`, `:506`; `admin_monthly_competitions_section.dart:379`; `admin_ui_kit.dart:42-61`, `:219`, `:278` | توجيه العُدّة إلى `AppCard/AppButton/AppTextField` وحذف المكرر. |
| UI-28 | المباريات | نسبة الفوز تُقرأ «86%» بلا اسم الفريق ولا «فوز»؛ شريحتا «فوز» و«%» تبدوان زرّين ولا تُلمسان. | `fotmob_match_card.dart:1443-1500` | تسمية «فوز فنلندا 86%»؛ إزالة إطار الشريحتين أو دمجهما. |
| UI-29 | الرئيسية، المشرف | «Vs» لاتينية داخل واجهة عربية؛ نحو 500 نص عربي مكتوب في الكود خارج `l10n` في 37 ملفًا (الرئيسية 27، أقسام المشرف أكثرها). | `home_screen.dart:290` | «ضد» أو «VS» موحّدة؛ نقل النصوص إلى ARB تدريجيًا مع كل دفعة. |
| UI-30 | حالات الفارغ/الخطأ | `AppEmptyState` و`AppErrorState` عمود في المنتصف بلا تمرير (فيض محتمل عند 2.0 أو أفقيًا)؛ الخطأ لا يُعلَن لقارئ الشاشة (`liveRegion`)؛ «نسخ رمز المشكلة» بلا تأكيد؛ «تعلّم من توقعاتك» يبني حالته الفارغة بنص حرّ. | `core/ui/app_empty_state.dart:30-33`; `core/ui/app_error_state.dart:33-36`; `features/gamification/insights_screen.dart:55-66` | `SingleChildScrollView`، `Semantics(liveRegion: true)`، رسالة «تم النسخ»، `AppEmptyState` في كل مكان. |
| UI-31 | الحساب | لا `switchTheme`: مفتاح الوضع الداكن يحدد لون الإبهام وحده فيأتي أزرق على أزرق، والمفتاح المطفأ في الفاتح رمادي Material الافتراضي. | `features/auth/account_screen.dart:414-423`; `core/theme/app_theme.dart` | `SwitchThemeData` من الرموز. |
| UI-33 | مشاركة الإصابة، البطل | لوحة ألوان مكررة يدويًا (`_navy`، `_gold`، `_muted`...) في ملفين؛ مقصودة لأن صورة المشاركة داكنة دائمًا، لكنها ستنحرف عن الرموز. | `features/history/exact_hit_share.dart:33-38`; `features/leaderboards/widgets/champion_spotlight.dart:43-48`, `:1123` | قراءة القيم من `AppColors` (الداكن) بدل نسخها. |

---

## 6. القيم المكتوبة يدويًا خارج `core/design` و`core/theme`

مستثنى: `core/branding/team_branding.dart` (ألوان الفرق بيانات لا تصميم). العدّ آلي من
الشجرة؛ خانة «height/width» تستثني ارتفاع السطر (`height: 1.2`).

| النوع | العدد |
|---|---:|
| لون حرفي (`Color(0x..)`، `Colors.*`، `AppColors` مباشرة) | 25 |
| نصف قطر رقمي | 27 |
| `EdgeInsets` برقم | 23 |
| `SizedBox` برقم | 55 |
| `height`/`width` رقمي (≥3) | 96 |
| `size:` رقمي (أيقونة/شعار) | 50 |
| شفافية حرفية `withValues(alpha)` | 53 |

الأخطر بينها (يغيّر معنى أو يكسر وضعًا): `fotmob_match_card.dart:478` (UI-08)،
`fixtures_date_bar.dart:241` (UI-02)، `nukhbaa_shell.dart:223` (UI-04)،
`segmented_pills.dart:41` (UI-15)، `live_matches_chip.dart:115` (UI-16)،
`leaderboard_board.dart:383-418` (UI-12). الجدول الكامل بالأسطر في الملحق أ.

---

## 7. دفعات الإصلاح المقترحة (بعد موافقتك)

| الدفعة | المحتوى | البنود | يُزال منها skip |
|---|---|---|---|
| 1 -- التباين من الرموز | رموز جديدة في `AppTokens`: `onGold`، `successText`، `errorText`، `badgeFill`؛ تدرّج النص الأبيض؛ أساس البطاقة `surface`. تغيير ألوان فقط، لا تخطيط. | UI-02، 03، 05، 06، 07، 08، 13، 26 | الأزواج في `app_tokens_pairs_contrast_test` + UI-02/03/05/06/07/08/13 |
| 2 -- اللمس والخط | مساحات لمس 48 بلا تغيير الشكل؛ الشريط السفلي؛ إزالة `FittedBox` من النصوص؛ أسماء الأزرار. | UI-01، 04، 15، 16، 17، 18، 27، 28 | UI-01/04/15/16/17/18/27 |
| 3 -- الهوية البصرية | (تحتاج قراراتك أدناه) غسلة الفرق، الذهبي الفاتح، حدود الفاتح، الرأس الموحّد، الأعلام، الحرف الأول، تعادل المنصة، زر التقويم، الفواصل. | UI-09، 10، 11، 12، 14، 19، 20، 21، 32 | UI-10/11/12/14/21 |
| 4 -- الويب والمشرف والتنظيف | تكبير الويب، لوحة المفاتيح، عُدّة المشرف، حالات الفارغ/الخطأ، المفاتيح، النصوص. | UI-22، 23، 24، 25، 29، 30، 31، 33 | UI-22/24 |

بعد كل دفعة: إعادة قياس خط الأساس (`UI_AUDIT_WRITE_BASELINE=true`) فينزل العدّاد ولا يعود.

### قرارات تحتاج موافقتك قبل الدفعة 3
1. **UI-09** غسلة ألوان الفرق على البطاقة: هالة حول الشعار فقط، أم 6%؟
2. **UI-32** الذهبي الفاتح: ذهبي زخرفي `#A87B00` للحلقات مع إبقاء الحالي للنص؟
3. **UI-20** رأس واحد للتبويبات الخمسة بلون الصفحة؟
4. **UI-01** منطقة لمس 48 مع بقاء الرسم 26، أم صندوق أطول 61×100؟

---

## 8. الاختبارات المضافة

| الملف | ماذا يفعل | الحالة الآن |
|---|---|---|
| `apps/mobile/test/core/theme/app_tokens_pairs_contrast_test.dart` | 25 زوجًا × سمتين من رموز `AppTheme` الحقيقية، كل زوج باسم الـ widget الذي يرسمه. | الناجح يمرّ؛ الراسب `skip` برقم البند |
| `apps/mobile/test/audit/ui_audit_survey_test.dart` | 16 شاشة × سمتين عبر الـ harness الموجود (`auth`، `current_month_fixtures`، `leaderboards`، `prediction`)، يطبّق `textContrastGuideline` و`androidTapTargetGuideline` و`labeledTapTargetGuideline` عند 1.0، ويجمع كل خطأ تخطيط عند 1.0 و1.3 و2.0. يكتب `build/ui_audit/findings.md`. | سقّاطة: العدد لكل شاشة/فحص لا يزيد عن `test/audit/ui_audit_baseline.json` |
| `apps/mobile/test/audit/ui_known_defects_test.dart` | 21 اختبارًا مركّزًا (20 عبر الـ widget الحقيقي + صفحة الويب)، كلٌّ يصف السلوك الصحيح بعد الإصلاح عبر الـ widget الحقيقي. | كلها `skip` برقم البند وسببه |
| `docs/reviews/ui-audit-2026-10-measured.md` | ناتج المسح على جهازك (يولّده السكربت). | يُضاف مع الـ commit |

---

## ملحق أ -- القيم اليدوية بالأسطر

| الملف | ألوان | أنصاف أقطار | مسافات/أحجام (أسطر) |
|---|---|---|---|
| `features/leaderboards/widgets/leaderboard_board.dart` | — | — | 251,383,393,402,413,500,503,511,533,587,649,733,762,765,772,842,859,896 |
| `features/fixture_prediction/widgets/fotmob_match_card.dart` | 478,1083,1625 | — | 625,638,653,1191,1196,1197,1224,1260,1274 |
| `features/leaderboards/widgets/champion_spotlight.dart` | 43,44,45,46,47,48,174,1123 | 1157 | 286,476,537,549,758,810,844,845,1189 |
| `features/admin/widgets/admin_ui_kit.dart` | — | 55,100,104,108,138,187,235,279 | 92,143,144,155,192,193,204,239,283,310,346 |
| `features/auth/home_screen.dart` | 462 | — | 72,75,84,89,101,109,118,122,353,393 |
| `features/fixture_prediction/fixture_prediction_screen.dart` | — | — | 103,116,128,166,170,171,179,606,616,638 |
| `features/admin/screens/sections/results_scoring_section.dart` | — | 370 | 365,366,396,397,409,420 |
| `features/admin/screens/sections/admin_dashboard_section.dart` | — | 150,276 | 47,146,147,283,353,392,436 |
| `features/admin/screens/sections/admin_monthly_competitions_section.dart` | 379 | 380 | 238,241,242,371,375,376,390 |
| `features/history/exact_hit_share.dart` | 33,34,35,36,37,38 | — | 225,240,241 |
| `features/admin/screens/sections/user_sanction_section.dart` | 458,506 | 446 | 405,538,760,840 |
| `features/auth/session_gate.dart` | — | — | 148,152,153,159,167 |
| `features/fixture_prediction/current_month_fixtures_screen.dart` | 292 | — | 424,461,465,466,474 |
| `features/gamification/daily_challenge_card.dart` | — | 166,248 | 145,168,245,255 |
| `features/record/elite_card_screen.dart` | — | — | 138,156,204,248,388,391 |
| `core/ui/match_card.dart` | — | — | 58,59,98,124,153,158 |
| `features/admin/screens/sections/admin_counted_fixtures_section.dart` | — | 103 | 44,96,97,124 |
| `features/history/prediction_history_screen.dart` | — | — | 260,415,542,543 |
| `features/gamification/my_badges_screen.dart` | — | — | 182,183,188,203 |
| `features/auth/nukhbaa_shell.dart` | — | — | 223,291,292 |
| `features/record/my_points_screen.dart` | — | 161,203,322 | 184 |
| `features/leaderboards/leaderboards_screen.dart` | — | — | 244,440,445,494 |
| `features/fixture_prediction/widgets/fixtures_calendar_page.dart` | — | — | 183,191,198,199 |
| `features/fixture_prediction/widgets/fixture_predictions_board_page.dart` | — | — | 395,396 |
| `core/ui/streak_chip.dart` | — | 19 | 16,25,26 |
| `features/update/update_gate.dart` | — | — | 477,484 |
| `features/leaderboards/champions_record_screen.dart` | — | — | 131,152,168 |
| `features/fixture_prediction/fixture_predict_sheet.dart` | — | 201 | 196,197 |
| `features/fixture_prediction/widgets/fixtures_date_bar.dart` | 241 | — | 206,228 |
| `features/fixture_prediction/widgets/live_matches_chip.dart` | — | — | 115,135,136 |
| `core/ui/app_skeleton.dart` | — | 66 | 103,109,111 |
| `features/gamification/insights_screen.dart` | — | 174 | 156,163 |
| `features/record/my_seasons_screen.dart` | — | — | 128,129,153 |
| `features/record/season_record_screen.dart` | — | — | 78,79,103 |
| `features/admin/admin_shell.dart` | — | — | 195 |
| `features/auth/sign_in_screen.dart` | — | — | 384 |
| `features/auth/password_reset_screen.dart` | — | — | 152,294 |
| `features/leaderboards/widgets/weekly_league_board.dart` | — | — | 225 |
| `core/error/error_reporter.dart` | 412 | — | 404 |
| `features/competition/widgets/async_list_view.dart` | — | — | 43 |
| `features/admin/screens/sections/admin_predictions_section.dart` | — | — | 185 |
| `features/admin/screens/sections/fixture_schedule_section.dart` | — | — | 37 |
| `features/admin/screens/sections/ledger_lookup_section.dart` | — | — | 58 |
| `features/admin/screens/sections/user_names_section.dart` | — | 416 | — |
| `features/admin/screens/sections/error_log_section.dart` | — | 537 | — |
| `features/admin/screens/sections/champion_admin_section.dart` | — | — | 564 |
| `features/admin/widgets/team_picker_field.dart` | — | 87 | — |
| `features/auth/account_screen.dart` | — | — | 317 |
| `features/auth/app_lock.dart` | — | — | 118 |
| `features/auth/widgets/account_menu.dart` | — | — | 100 |
| `features/notifications/notification_settings_screen.dart` | — | — | 200 |
| `features/leaderboards/widgets/champion_crown.dart` | 40 | — | — |
| `features/groups/group_feed_screen.dart` | — | — | 84 |
| `core/ui/team_logo.dart` | — | — | 144 |
