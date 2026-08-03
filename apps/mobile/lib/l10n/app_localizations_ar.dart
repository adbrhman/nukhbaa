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
}
