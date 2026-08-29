// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'نُخبة';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get error => 'حدث خطأ ما';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get showPassword => 'إظهار كلمة المرور';

  @override
  String get hidePassword => 'إخفاء كلمة المرور';

  @override
  String get markNotificationRead => 'تعليم كمقروءة';

  @override
  String get createAccount => 'إنشاء حساب';

  @override
  String get signInSubtitle =>
      'سجّل الدخول بالبريد الإلكتروني وكلمة المرور للمتابعة.';

  @override
  String get signUpSubtitle => 'أنشئ حساباً لتبدأ اللعب في نُخبة.';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get emailHint => 'you@example.com';

  @override
  String get emailRequired => 'الرجاء إدخال بريدك الإلكتروني.';

  @override
  String get password => 'كلمة المرور';

  @override
  String get passwordRequired => 'الرجاء إدخال كلمة المرور.';

  @override
  String get displayName => 'الاسم';

  @override
  String get displayNameHint => 'اسمك الظاهر للآخرين';

  @override
  String get displayNameRequired => 'الرجاء إدخال اسمك.';

  @override
  String get changeDisplayName => 'تغيير الاسم';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get toggleToSignIn => 'لديك حساب بالفعل؟ سجّل الدخول';

  @override
  String get toggleToRegister => 'جديد هنا؟ أنشئ حساباً';

  @override
  String get tagline => 'منصة توقعات كرة القدم';

  @override
  String get authTabSignIn => 'دخول';

  @override
  String get authTabRegister => 'تسجيل';

  @override
  String get confirmPassword => 'تأكيد كلمة المرور';

  @override
  String get confirmPasswordRequired => 'الرجاء تأكيد كلمة المرور.';

  @override
  String get passwordMismatch => 'كلمتا المرور غير متطابقتين.';

  @override
  String get rulesTitle => 'كيف تلعب؟';

  @override
  String get rulesTagline => 'توقع، نافس، تصدّر، كن من النخبة';

  @override
  String get rulesPredictMajorLeagues => 'توقع مباريات الدوريات الكبرى';

  @override
  String get rulesCorrectPrediction => 'التوقع الصحيح: 3 نقاط';

  @override
  String get rulesWrongPrediction => 'التوقع الخاطئ: 0 نقطة';

  @override
  String get rulesDoubleMatch => 'المباراة المختارة كدبل: 6 نقاط';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get signedIn => 'تم تسجيل الدخول';

  @override
  String get userId => 'معرّف المستخدم';

  @override
  String get role => 'الدور';

  @override
  String get status => 'الحالة';

  @override
  String get browseCompetitions => 'تصفح البطولات';

  @override
  String get hallOfFame => 'قاعة المشاهير';

  @override
  String get myPredictions => 'توقعاتي';

  @override
  String get createGroup => 'إنشاء مجموعة';

  @override
  String get joinGroup => 'الانضمام إلى مجموعة';

  @override
  String get adminDashboard => 'لوحة تحكم المشرف';

  @override
  String get hallOfFameEmpty => 'لم يحصل أحد على أي نقاط بعد.';

  @override
  String hallOfFameSeasonsPlayed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'شارك في $count موسم',
      many: 'شارك في $count موسمًا',
      few: 'شارك في $count مواسم',
      two: 'شارك في موسمين',
      one: 'شارك في موسم واحد',
      zero: 'لم يشارك في أي موسم',
    );
    return '$_temp0';
  }

  @override
  String get competitionSeasonsEmpty => 'لا توجد مواسم لهذه البطولة بعد.';

  @override
  String leaderboardTitle(String label) {
    return '$label — لوحة الصدارة';
  }

  @override
  String get seasonLeaderboardEmpty => 'لم ينضم أحد لهذا الموسم بعد.';

  @override
  String leaderboardEntriesCounted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مشاركة محتسبة',
      many: '$count مشاركة محتسبة',
      few: '$count مشاركات محتسبة',
      two: 'مشاركتان محتسبتان',
      one: 'مشاركة واحدة محتسبة',
      zero: 'لا توجد مشاركات محتسبة',
    );
    return '$_temp0';
  }

  @override
  String pointsAbbreviated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نقطة',
      many: '$count نقطة',
      few: '$count نقاط',
      two: 'نقطتان',
      one: 'نقطة واحدة',
      zero: '0 نقطة',
    );
    return '$_temp0';
  }

  @override
  String get seasonLeaderboardTab => 'نقاط الموسم';

  @override
  String get fixtureLeaderboardTab => 'نقاط المباريات';

  @override
  String get fixtureLeaderboardEmpty =>
      'لا توجد مباراة محتسبة بعد في هذا الموسم.';

  @override
  String get selectRoundLabel => 'اختر الجولة';

  @override
  String get roundKingLabel => 'ملك الجولة';

  @override
  String get groupLeaderboardEmpty =>
      'لم ينضم أي عضو من هذه المجموعة للموسم بعد.';

  @override
  String get competitions => 'المسابقات';

  @override
  String get competitionsEmpty => 'لا توجد مسابقات للتصفح حتى الآن.';

  @override
  String get visibilityPublic => 'عام';

  @override
  String get visibilityPrivate => 'خاص';

  @override
  String get predictionHistoryEmpty => 'لم تقدّم أي توقعات بعد.';

  @override
  String predictionHistoryScoreLine(
    String fixtureId,
    int homeGoals,
    int awayGoals,
  ) {
    return '$fixtureId: $homeGoals - $awayGoals';
  }

  @override
  String groupFeedTitle(String groupName) {
    return 'نشاط $groupName';
  }

  @override
  String get groupFeedEmpty => 'لا يوجد نشاط بعد.';

  @override
  String get activityRoundScored => 'تم احتساب نتيجة الجولة';

  @override
  String get activityMemberJoined => 'انضم عضو جديد';

  @override
  String activityRankShift(int oldRank, int newRank) {
    return 'انتقل من المركز #$oldRank إلى #$newRank';
  }

  @override
  String get activityRankShiftUnknown => 'تغيّر الترتيب';

  @override
  String seasonRoundsTitle(String seasonLabel) {
    return '$seasonLabel — الجولات';
  }

  @override
  String get viewLeaderboardTooltip => 'عرض لوحة الصدارة';

  @override
  String get fixturePredictionTooltip => 'توقّع مباريات الموسم';

  @override
  String get seasonRoundsEmpty => 'لا توجد جولات لهذا الموسم بعد.';

  @override
  String roundItemTitle(int sequence) {
    return 'الجولة $sequence';
  }

  @override
  String roundDeadlineLine(String statusLabel, String deadline) {
    return '$statusLabel · الموعد النهائي $deadline';
  }

  @override
  String get roundStatusOpen => 'مفتوحة للتوقعات';

  @override
  String get roundStatusLocked => 'مغلقة';

  @override
  String get roundStatusScored => 'محتسبة';

  @override
  String get roundFixturesTitle => 'الجولة';

  @override
  String roundRulesLine(String statusLabel, int rulesetVersion) {
    return '$statusLabel · القواعد إصدار $rulesetVersion';
  }

  @override
  String get predictRoundButton => 'توقع نتائج هذه الجولة';

  @override
  String get roundFixturesEmpty => 'لا توجد مباريات لهذه الجولة بعد.';

  @override
  String fixtureItemTitle(String fixtureId) {
    return 'المباراة $fixtureId';
  }

  @override
  String fixtureVsTitle(String home, String away) {
    return '$home ضد $away';
  }

  @override
  String get predictionTitle => 'التوقّع';

  @override
  String predictionClosedMessage(String status) {
    return 'هذه الجولة $status. التوقعات مغلقة.';
  }

  @override
  String get predictionNotYetPredictableMessage =>
      'يمكنك التوقع لهذه الجولة بعد إغلاق الجولة السابقة';

  @override
  String get genericErrorMessage => 'حدث خطأ ما. يُرجى المحاولة مرة أخرى.';

  @override
  String get tryAgainButton => 'حاول مرة أخرى';

  @override
  String get predictionAlreadySubmitted =>
      'لقد أرسلت توقعاً لهذه الجولة مسبقاً. التعديل والإرسال مرة أخرى سيحدّثه.';

  @override
  String get predictionSaved => 'تم حفظ توقعك.';

  @override
  String get submitPredictionButton => 'إرسال التوقع';

  @override
  String get predictionDoubleLabel => 'الدبل';

  @override
  String get predictionFixtureLockedLabel => 'بدأت المباراة';

  @override
  String get predictionDoubleHint => 'اختر مباراة واحدة كدبل قبل الإرسال.';

  @override
  String get predictionIncompleteHint =>
      'أدخل نتيجة كل مباراة مفتوحة قبل الإرسال.';

  @override
  String get predictionNoOpenFixturesMessage =>
      'كل مباريات هذه الجولة بدأت بالفعل. لا يوجد ما يمكن توقّعه الآن.';

  @override
  String get fixturePredictionTitle => 'توقّع مباريات الموسم';

  @override
  String get fixturePredictionEmptyMessage =>
      'لا توجد مباريات مرتبطة بهذا الموسم بعد.';

  @override
  String get fixturePredictionSavedMessage => 'تم حفظ توقعك لهذه المباراة.';

  @override
  String get submitFixturePredictionButton => 'إرسال';

  @override
  String get matchesTitle => 'المباريات';

  @override
  String get matchesEmpty => 'لا توجد مباريات مفتوحة حالياً.';

  @override
  String get adminAuditLogTab => 'سجل التدقيق';

  @override
  String get adminUsersTab => 'المستخدمون';

  @override
  String get adminLedgerLookupTab => 'البحث في السجل المالي';

  @override
  String get adminAuditLogEmpty => 'لا توجد إدخالات تدقيق بعد.';

  @override
  String get adminReasonMandatoryLabel => 'السبب (إلزامي)';

  @override
  String get adminSuspendButton => 'تعليق';

  @override
  String get adminReinstateButton => 'إعادة تفعيل';

  @override
  String get adminUsersSearchLabel => 'ابحث بالبريد الإلكتروني';

  @override
  String get adminUsersEmptyResults => 'لا يوجد مستخدمون مطابقون.';

  @override
  String adminSanctionResultMessage(String userId, String status) {
    return 'المستخدم $userId أصبح الآن $status';
  }

  @override
  String get adminParticipantIdLabel => 'معرّف المشارك';

  @override
  String get adminLookUpButton => 'بحث';

  @override
  String get adminFixturesTab => 'هوية المباراة';

  @override
  String get adminFixtureIdOptionalLabel =>
      'معرّف المباراة (للتصحيح فقط، اتركه فارغاً للتسجيل)';

  @override
  String get adminSelectCompetitionLabel => 'اختار الدوري (المسابقات)';

  @override
  String get adminHomeTeamLabel => 'الفريق المضيف';

  @override
  String get adminAwayTeamLabel => 'الفريق الضيف';

  @override
  String get adminPickKickoffButton => 'اختر موعد المباراة';

  @override
  String get adminRegisterFixtureButton => 'تسجيل مباراة جديدة';

  @override
  String get adminCorrectFixtureButton => 'تصحيح المباراة';

  @override
  String get adminResultsScoringTab => 'النتائج والاحتساب';

  @override
  String get adminSeasonIdLabel => 'معرّف الموسم';

  @override
  String get adminLinkFixtureSectionTitle => 'ربط مباراة بجولة';

  @override
  String get adminRoundIdLabel => 'معرّف الجولة';

  @override
  String get adminFixtureIdLabel => 'معرّف المباراة';

  @override
  String get adminDisplayOrderLabel => 'ترتيب العرض';

  @override
  String get adminLinkFixtureButton => 'ربط المباراة بالجولة';

  @override
  String get adminScoringTab => 'النتائج والاحتساب';

  @override
  String get adminRecordResultSectionTitle => 'تسجيل نتيجة مباراة';

  @override
  String get adminHomeGoalsLabel => 'أهداف المضيف';

  @override
  String get adminAwayGoalsLabel => 'أهداف الضيف';

  @override
  String get adminRecordResultButton => 'تسجيل النتيجة';

  @override
  String get adminScoreFixtureButton => 'احتساب المباراة';

  @override
  String get adminPostFixtureLedgerButton => 'ترحيل إلى السجل';

  @override
  String get adminScoreRoundSectionTitle => 'احتساب نقاط الجولة';

  @override
  String get adminScoreRoundButton => 'احتساب الجولة';

  @override
  String get adminPostToLedgerButton => 'ترحيل النقاط للسجل';

  @override
  String get adminPostToLedgerSuccessLabel => 'تم الترحيل، عدد القيود الجديدة';

  @override
  String get adminRoundScoresSectionTitle => 'نتائج المشاركين بالجولة';

  @override
  String get adminViewScoresButton => 'عرض النتائج';

  @override
  String get adminTotalPointsLabel => 'مجموع النقاط';

  @override
  String get adminRoundReportSectionTitle => 'تقرير الجولة';

  @override
  String get adminViewRoundReportButton => 'عرض تقرير الجولة';

  @override
  String get adminRoundReportRankLabel => 'الترتيب';

  @override
  String get adminRoundReportShareButton => 'نسخ للمشاركة';

  @override
  String get adminRoundReportCopiedMessage => 'تم النسخ، شاركه عبر واتساب';

  @override
  String get adminRoundReportEmpty => 'لا يوجد مشاركون بهذه الجولة';

  @override
  String get adminRoundReportSectionEmpty => 'لا يوجد تقرير لهذه الجولة بعد';

  @override
  String get adminViewFixtureReportButton => 'عرض تقرير المباراة';

  @override
  String get adminFixtureReportSectionEmpty =>
      'لا يوجد تقرير لهذه المباراة بعد';

  @override
  String get myActiveSeasons => 'مواسمي النشطة';

  @override
  String get myActiveSeasonsEmpty => 'لا مواسم نشطة لك حاليًا.';

  @override
  String get myGroups => 'مجموعاتي';

  @override
  String get myGroupsEmpty => 'لم تنضم إلى أي مجموعة بعد.';

  @override
  String get groupRoleOwner => 'مالك';

  @override
  String get groupRoleMember => 'عضو';

  @override
  String groupMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عضو',
      many: '$count عضوًا',
      few: '$count أعضاء',
      two: 'عضوان',
      one: 'عضو واحد',
      zero: 'لا يوجد أعضاء',
    );
    return '$_temp0';
  }

  @override
  String get createGroupTitle => 'إنشاء مجموعة';

  @override
  String get groupNameLabel => 'اسم المجموعة';

  @override
  String get createGroupButton => 'إنشاء';

  @override
  String get joinGroupTitle => 'الانضمام إلى مجموعة';

  @override
  String get inviteCodeLabel => 'رمز الدعوة';

  @override
  String get joinGroupButton => 'انضمام';

  @override
  String get groupCreatedTitle => 'تم إنشاء المجموعة';

  @override
  String get groupInviteCodeHint => 'شارك هذا الرمز مع من تريد دعوته للانضمام';

  @override
  String get copyInviteCodeButton => 'نسخ الرمز';

  @override
  String get inviteCodeCopiedMessage => 'تم نسخ رمز الدعوة';

  @override
  String get doneButton => 'تم';

  @override
  String get ledgerTitle => 'نقاطي';

  @override
  String get ledgerEmpty => 'لا توجد حركات نقاط بعد.';

  @override
  String ledgerEntryCount(int count) {
    return '$count حركة مسجّلة';
  }

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get notificationsEmpty => 'ليس لديك أي إشعارات بعد.';

  @override
  String get notificationRoundScored => 'تم تسجيل نتيجة جولة توقعتها';

  @override
  String get notificationGroupMemberJoined => 'انضم شخص إلى مجموعتك';

  @override
  String get notificationReactionReceived => 'تلقيت تفاعلاً';

  @override
  String get notificationsMarkAsRead => 'تمييز كمقروء';

  @override
  String get adminAddMatchSectionTitle => 'تسجيل مباراة وإضافتها لجولة';

  @override
  String get adminSelectSeasonLabel => 'اختر الموسم';

  @override
  String get adminSelectRoundLabel => 'اختر الجولة';

  @override
  String get adminNoSeasonsHint => 'لا توجد مواسم لهذه المسابقة.';

  @override
  String get adminNoRoundsHint =>
      'لا توجد جولات لهذا الموسم. افتح جولة أولاً من تبويب الجولات.';

  @override
  String get adminSelectFixtureLabel => 'اختر المباراة';

  @override
  String get adminNoFixturesHint => 'لا توجد مباريات في هذه الجولة.';

  @override
  String get adminFixtureIncompleteDataLabel => 'مباراة غير مكتملة البيانات';

  @override
  String adminRoundOptionLabel(int sequence, String status) {
    return 'الجولة $sequence — $status';
  }

  @override
  String get adminAddMatchButton => 'تسجيل المباراة وإضافتها للجولة';

  @override
  String adminAddMatchSuccess(String home, String away) {
    return 'تمت إضافة $home ضد $away إلى الموسم.';
  }

  @override
  String get adminSelectRoundFirst => 'اختر الجولة أولاً.';

  @override
  String get adminExistingFixturesSectionTitle => 'مباريات هذه الجولة';

  @override
  String get adminRemoveFixtureTooltip => 'حذف هذه المباراة من الجولة';

  @override
  String get adminRemoveFixtureConfirmTitle => 'حذف المباراة؟';

  @override
  String adminRemoveFixtureConfirmMessage(String home, String away) {
    return 'حذف $home ضد $away من هذه الجولة؟ لا يمكن التراجع عن هذا الإجراء.';
  }

  @override
  String get adminRemoveFixtureConfirmButton => 'حذف';

  @override
  String get adminRemoveFixtureCancelButton => 'إلغاء';

  @override
  String get adminRemoveFixtureSuccess => 'تم حذف المباراة من الجولة.';
}
