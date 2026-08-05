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
  String get toggleToSignIn => 'لديك حساب بالفعل؟ سجّل الدخول';

  @override
  String get toggleToRegister => 'جديد هنا؟ أنشئ حساباً';

  @override
  String get tagline => 'منصة توقعات كرة القدم';

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
  String get predictionTitle => 'التوقّع';

  @override
  String predictionClosedMessage(String status) {
    return 'هذه الجولة $status. التوقعات مغلقة.';
  }

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
  String get adminParticipantIdLabel => 'معرّف المشارك';

  @override
  String get adminLookUpButton => 'بحث';

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
}
