#!/usr/bin/env python3
"""step_login_screen_migration — نقل شاشة تسجيل الدخول من التطبيق القديم
(index_html.txt) إلى apps/mobile الجديد، بدون أي تغيير على ألوان AppTokens.

يضيف:
  1) تبويب دخول/تسجيل (Tabs) بدل زر النص بالأسفل — مطابق لتصميم القديم،
     ألوان من AppTokens الحالية فقط.
  2) حقل تأكيد كلمة المرور بوضع التسجيل (تحقق محلي فقط، لا تغيير بالباك اند —
     SessionController.register ما زال يقبل email/password فقط).
  3) صندوق "كيف تلعب؟" بوضع التسجيل (نص المستخدم الفعلي: توقع صحيح 3 نقاط،
     توقع خاطئ 0 نقطة، مباراة مختارة كدبل 6 نقاط).
  4) 11 مفتاح ترجمة جديد (ar/en) بالـ arb + الملفات المولَّدة يدوياً
     (Flutter SDK غير متاح بـ Termux لـ apps/mobile، فالتوليد يدوي كالمعتاد).

خارج النطاق عمداً (فجوة معمارية حقيقية):
  Google OAuth، تسجيل الدخول بالبصمة (WebAuthn)، تبويب دخول المشرف المنفصل،
  حقل الاسم الكامل بالتسجيل، بطاقة المباراة المباشرة. راجع شرح الجلسة.

تعديلات ملفات l10n الخمسة = str.replace على تطابق حرفي واحد بالضبط؛ أي عدم
تطابق يوقف السكربت بخطأ صريح قبل كتابة أي شيء لذلك الملف.

ملف sign_in_screen.dart وحده (521 سطر جديد) لا يُعدَّل بـ str.replace — بل
يُستبدل بالكامل عبر فك تشفير base64 (تجنّباً لمشكلة تقطّع لصق الهيردوكس
الكبيرة بمحرر Termux، الملاحظة الموثّقة من جلسة سابقة)، بعد التأكد أولاً أن
الملف الحالي فيه العلامة المتوقعة (signIn.toggleMode) لضمان عدم الكتابة فوق
نسخة مُعدَّلة مسبقاً بدون علم.

بعد التشغيل: dart analyze apps/mobile && dart test apps/mobile (بعد استثناء
apps/mobile من pubspec.yaml مؤقتاً كالمعتاد إن احتجت، أو عبر flutter analyze
إن كان متاحاً بالـ Codespace).
"""

import base64
import sys

EDITS = {
    "apps/mobile/lib/l10n/app_ar.arb": [
        (
            '  "tagline": "منصة توقعات كرة القدم",\n'
            '  "notifications": "الإشعارات",',
            '  "tagline": "منصة توقعات كرة القدم",\n'
            '  "authTabSignIn": "دخول",\n'
            '  "authTabRegister": "تسجيل",\n'
            '  "confirmPassword": "تأكيد كلمة المرور",\n'
            '  "confirmPasswordRequired": "الرجاء تأكيد كلمة المرور.",\n'
            '  "passwordMismatch": "كلمتا المرور غير متطابقتين.",\n'
            '  "rulesTitle": "كيف تلعب؟",\n'
            '  "rulesTagline": "توقع، نافس، تصدّر، كن من النخبة",\n'
            '  "rulesPredictMajorLeagues": "توقع مباريات الدوريات الكبرى",\n'
            '  "rulesCorrectPrediction": "التوقع الصحيح: 3 نقاط",\n'
            '  "rulesWrongPrediction": "التوقع الخاطئ: 0 نقطة",\n'
            '  "rulesDoubleMatch": "المباراة المختارة كدبل: 6 نقاط",\n'
            '  "notifications": "الإشعارات",',
        ),
    ],
    "apps/mobile/lib/l10n/app_en.arb": [
        (
            '  "tagline": "Football prediction platform",\n'
            '  "notifications": "Notifications",',
            '  "tagline": "Football prediction platform",\n'
            '  "authTabSignIn": "Sign in",\n'
            '  "authTabRegister": "Register",\n'
            '  "confirmPassword": "Confirm password",\n'
            '  "confirmPasswordRequired": "Please confirm your password.",\n'
            '  "passwordMismatch": "Passwords do not match.",\n'
            '  "rulesTitle": "How to play?",\n'
            '  "rulesTagline": "Predict, compete, top the table, be Nukhba.",\n'
            '  "rulesPredictMajorLeagues": "Predict matches from the major leagues",\n'
            '  "rulesCorrectPrediction": "Correct prediction: 3 points",\n'
            '  "rulesWrongPrediction": "Wrong prediction: 0 points",\n'
            '  "rulesDoubleMatch": "Match picked as double: 6 points",\n'
            '  "notifications": "Notifications",',
        ),
    ],
    "apps/mobile/lib/l10n/app_localizations.dart": [
        (
            "  /// In en, this message translates to:\n"
            "  /// **'Football prediction platform'**\n"
            "  String get tagline;\n"
            "\n"
            "  /// No description provided for @notifications.",
            "  /// In en, this message translates to:\n"
            "  /// **'Football prediction platform'**\n"
            "  String get tagline;\n"
            "\n"
            "  /// No description provided for @authTabSignIn.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Sign in'**\n"
            "  String get authTabSignIn;\n"
            "\n"
            "  /// No description provided for @authTabRegister.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Register'**\n"
            "  String get authTabRegister;\n"
            "\n"
            "  /// No description provided for @confirmPassword.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Confirm password'**\n"
            "  String get confirmPassword;\n"
            "\n"
            "  /// No description provided for @confirmPasswordRequired.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Please confirm your password.'**\n"
            "  String get confirmPasswordRequired;\n"
            "\n"
            "  /// No description provided for @passwordMismatch.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Passwords do not match.'**\n"
            "  String get passwordMismatch;\n"
            "\n"
            "  /// No description provided for @rulesTitle.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'How to play?'**\n"
            "  String get rulesTitle;\n"
            "\n"
            "  /// No description provided for @rulesTagline.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Predict, compete, top the table, be Nukhba.'**\n"
            "  String get rulesTagline;\n"
            "\n"
            "  /// No description provided for @rulesPredictMajorLeagues.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Predict matches from the major leagues'**\n"
            "  String get rulesPredictMajorLeagues;\n"
            "\n"
            "  /// No description provided for @rulesCorrectPrediction.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Correct prediction: 3 points'**\n"
            "  String get rulesCorrectPrediction;\n"
            "\n"
            "  /// No description provided for @rulesWrongPrediction.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Wrong prediction: 0 points'**\n"
            "  String get rulesWrongPrediction;\n"
            "\n"
            "  /// No description provided for @rulesDoubleMatch.\n"
            "  ///\n"
            "  /// In en, this message translates to:\n"
            "  /// **'Match picked as double: 6 points'**\n"
            "  String get rulesDoubleMatch;\n"
            "\n"
            "  /// No description provided for @notifications.",
        ),
    ],
    "apps/mobile/lib/l10n/app_localizations_ar.dart": [
        (
            "  @override\n"
            "  String get tagline => 'منصة توقعات كرة القدم';\n"
            "\n"
            "  @override\n"
            "  String get notifications => 'الإشعارات';",
            "  @override\n"
            "  String get tagline => 'منصة توقعات كرة القدم';\n"
            "\n"
            "  @override\n"
            "  String get authTabSignIn => 'دخول';\n"
            "\n"
            "  @override\n"
            "  String get authTabRegister => 'تسجيل';\n"
            "\n"
            "  @override\n"
            "  String get confirmPassword => 'تأكيد كلمة المرور';\n"
            "\n"
            "  @override\n"
            "  String get confirmPasswordRequired => 'الرجاء تأكيد كلمة المرور.';\n"
            "\n"
            "  @override\n"
            "  String get passwordMismatch => 'كلمتا المرور غير متطابقتين.';\n"
            "\n"
            "  @override\n"
            "  String get rulesTitle => 'كيف تلعب؟';\n"
            "\n"
            "  @override\n"
            "  String get rulesTagline => 'توقع، نافس، تصدّر، كن من النخبة';\n"
            "\n"
            "  @override\n"
            "  String get rulesPredictMajorLeagues => 'توقع مباريات الدوريات الكبرى';\n"
            "\n"
            "  @override\n"
            "  String get rulesCorrectPrediction => 'التوقع الصحيح: 3 نقاط';\n"
            "\n"
            "  @override\n"
            "  String get rulesWrongPrediction => 'التوقع الخاطئ: 0 نقطة';\n"
            "\n"
            "  @override\n"
            "  String get rulesDoubleMatch => 'المباراة المختارة كدبل: 6 نقاط';\n"
            "\n"
            "  @override\n"
            "  String get notifications => 'الإشعارات';",
        ),
    ],
    "apps/mobile/lib/l10n/app_localizations_en.dart": [
        (
            "  @override\n"
            "  String get tagline => 'Football prediction platform';\n"
            "\n"
            "  @override\n"
            "  String get notifications => 'Notifications';",
            "  @override\n"
            "  String get tagline => 'Football prediction platform';\n"
            "\n"
            "  @override\n"
            "  String get authTabSignIn => 'Sign in';\n"
            "\n"
            "  @override\n"
            "  String get authTabRegister => 'Register';\n"
            "\n"
            "  @override\n"
            "  String get confirmPassword => 'Confirm password';\n"
            "\n"
            "  @override\n"
            "  String get confirmPasswordRequired => 'Please confirm your password.';\n"
            "\n"
            "  @override\n"
            "  String get passwordMismatch => 'Passwords do not match.';\n"
            "\n"
            "  @override\n"
            "  String get rulesTitle => 'How to play?';\n"
            "\n"
            "  @override\n"
            "  String get rulesTagline => 'Predict, compete, top the table, be Nukhba.';\n"
            "\n"
            "  @override\n"
            "  String get rulesPredictMajorLeagues =>\n"
            "      'Predict matches from the major leagues';\n"
            "\n"
            "  @override\n"
            "  String get rulesCorrectPrediction => 'Correct prediction: 3 points';\n"
            "\n"
            "  @override\n"
            "  String get rulesWrongPrediction => 'Wrong prediction: 0 points';\n"
            "\n"
            "  @override\n"
            "  String get rulesDoubleMatch => 'Match picked as double: 6 points';\n"
            "\n"
            "  @override\n"
            "  String get notifications => 'Notifications';",
        ),
    ],
}

# apps/mobile/lib/features/auth/sign_in_screen.dart — استبدال كامل عبر base64
# (521 سطر جديد؛ أكبر من حد الـ 200 سطر اللي سبق وتقطّع لصقه بـ Termux).
SIGN_IN_SCREEN_PATH = "apps/mobile/lib/features/auth/sign_in_screen.dart"
SIGN_IN_SCREEN_MARKER = "key: const Key('signIn.toggleMode')"
SIGN_IN_SCREEN_NEW_B64 = "bGlicmFyeTsKCmltcG9ydCAnZGFydDphc3luYyc7CmltcG9ydCAncGFja2FnZTpmbHV0dGVyL21hdGVyaWFsLmRhcnQnOwppbXBvcnQgJ3BhY2thZ2U6Zmx1dHRlcl9yaXZlcnBvZC9mbHV0dGVyX3JpdmVycG9kLmRhcnQnOwppbXBvcnQgJ3BhY2thZ2U6c2hhcmVkL3NoYXJlZC5kYXJ0JzsKaW1wb3J0ICcuLi8uLi9jb3JlL2Rlc2lnbi9hcHBfcmFkaXVzLmRhcnQnOwppbXBvcnQgJy4uLy4uL2NvcmUvZGVzaWduL2FwcF9zaXplcy5kYXJ0JzsKaW1wb3J0ICcuLi8uLi9jb3JlL2Rlc2lnbi9hcHBfc3BhY2luZy5kYXJ0JzsKaW1wb3J0ICcuLi8uLi9jb3JlL2Rlc2lnbi9hcHBfbW90aW9uLmRhcnQnOwppbXBvcnQgJy4uLy4uL2NvcmUvZGVzaWduL2FwcF90b2tlbnMuZGFydCc7CmltcG9ydCAnLi4vLi4vY29yZS9lcnJvci9lcnJvcl9wcmVzZW50ZXIuZGFydCc7CmltcG9ydCAnLi4vLi4vY29yZS91aS9hcHBfYnV0dG9uLmRhcnQnOwppbXBvcnQgJy4uLy4uL2NvcmUvdWkvYXBwX3RleHRfZmllbGQuZGFydCc7CmltcG9ydCAnLi4vLi4vbDEwbi9hcHBfbG9jYWxpemF0aW9ucy5kYXJ0JzsKaW1wb3J0ICdzZXNzaW9uX2NvbnRyb2xsZXIuZGFydCc7CmltcG9ydCAnc2Vzc2lvbl9zdGF0ZS5kYXJ0JzsKCmNsYXNzIFNpZ25JblNjcmVlbiBleHRlbmRzIENvbnN1bWVyU3RhdGVmdWxXaWRnZXQgewogIGNvbnN0IFNpZ25JblNjcmVlbih7c3VwZXIua2V5fSk7CiAgQG92ZXJyaWRlCiAgQ29uc3VtZXJTdGF0ZTxTaWduSW5TY3JlZW4+IGNyZWF0ZVN0YXRlKCkgPT4gX1NpZ25JblNjcmVlblN0YXRlKCk7Cn0KCmNsYXNzIF9TaWduSW5TY3JlZW5TdGF0ZSBleHRlbmRzIENvbnN1bWVyU3RhdGU8U2lnbkluU2NyZWVuPiB7CiAgZmluYWwgVGV4dEVkaXRpbmdDb250cm9sbGVyIF9lbWFpbENvbnRyb2xsZXIgPSBUZXh0RWRpdGluZ0NvbnRyb2xsZXIoKTsKICBmaW5hbCBUZXh0RWRpdGluZ0NvbnRyb2xsZXIgX3Bhc3N3b3JkQ29udHJvbGxlciA9IFRleHRFZGl0aW5nQ29udHJvbGxlcigpOwogIGZpbmFsIFRleHRFZGl0aW5nQ29udHJvbGxlciBfY29uZmlybVBhc3N3b3JkQ29udHJvbGxlciA9CiAgICAgIFRleHRFZGl0aW5nQ29udHJvbGxlcigpOwogIGZpbmFsIEdsb2JhbEtleTxGb3JtU3RhdGU+IF9mb3JtS2V5ID0gR2xvYmFsS2V5PEZvcm1TdGF0ZT4oKTsKICBib29sIF9pc1JlZ2lzdGVyID0gZmFsc2U7CgogIEBvdmVycmlkZQogIHZvaWQgZGlzcG9zZSgpIHsKICAgIF9lbWFpbENvbnRyb2xsZXIuZGlzcG9zZSgpOwogICAgX3Bhc3N3b3JkQ29udHJvbGxlci5kaXNwb3NlKCk7CiAgICBfY29uZmlybVBhc3N3b3JkQ29udHJvbGxlci5kaXNwb3NlKCk7CiAgICBzdXBlci5kaXNwb3NlKCk7CiAgfQoKICB2b2lkIF9zdWJtaXQoU2Vzc2lvblN0YXRlIGN1cnJlbnQpIHsKICAgIGlmIChjdXJyZW50IGlzIFNlc3Npb25BdXRoZW50aWNhdGluZykgcmV0dXJuOwogICAgaWYgKCEoX2Zvcm1LZXkuY3VycmVudFN0YXRlPy52YWxpZGF0ZSgpID8/IGZhbHNlKSkgcmV0dXJuOwogICAgdW5hd2FpdGVkKAogICAgICBfaXNSZWdpc3RlcgogICAgICAgICAgPyByZWYKICAgICAgICAgICAgICAgIC5yZWFkKHNlc3Npb25Db250cm9sbGVyUHJvdmlkZXIubm90aWZpZXIpCiAgICAgICAgICAgICAgICAucmVnaXN0ZXIoCiAgICAgICAgICAgICAgICAgIGVtYWlsOiBfZW1haWxDb250cm9sbGVyLnRleHQudHJpbSgpLAogICAgICAgICAgICAgICAgICBwYXNzd29yZDogX3Bhc3N3b3JkQ29udHJvbGxlci50ZXh0LAogICAgICAgICAgICAgICAgKQogICAgICAgICAgOiByZWYKICAgICAgICAgICAgICAgIC5yZWFkKHNlc3Npb25Db250cm9sbGVyUHJvdmlkZXIubm90aWZpZXIpCiAgICAgICAgICAgICAgICAuc2lnbkluV2l0aENyZWRlbnRpYWxzKAogICAgICAgICAgICAgICAgICBlbWFpbDogX2VtYWlsQ29udHJvbGxlci50ZXh0LnRyaW0oKSwKICAgICAgICAgICAgICAgICAgcGFzc3dvcmQ6IF9wYXNzd29yZENvbnRyb2xsZXIudGV4dCwKICAgICAgICAgICAgICAgICksCiAgICApOwogIH0KCiAgdm9pZCBfc2V0TW9kZShib29sIHRvUmVnaXN0ZXIpIHsKICAgIGlmIChfaXNSZWdpc3RlciA9PSB0b1JlZ2lzdGVyKSByZXR1cm47CiAgICByZWYucmVhZChzZXNzaW9uQ29udHJvbGxlclByb3ZpZGVyLm5vdGlmaWVyKS5jbGVhckZhaWx1cmUoKTsKICAgIF9jb25maXJtUGFzc3dvcmRDb250cm9sbGVyLmNsZWFyKCk7CiAgICBzZXRTdGF0ZSgoKSA9PiBfaXNSZWdpc3RlciA9IHRvUmVnaXN0ZXIpOwogIH0KCiAgQG92ZXJyaWRlCiAgV2lkZ2V0IGJ1aWxkKEJ1aWxkQ29udGV4dCBjb250ZXh0KSB7CiAgICBmaW5hbCBBc3luY1ZhbHVlPFNlc3Npb25TdGF0ZT4gYXN5bmNTZXNzaW9uID0gcmVmLndhdGNoKAogICAgICBzZXNzaW9uQ29udHJvbGxlclByb3ZpZGVyLAogICAgKTsKICAgIGZpbmFsIFNlc3Npb25TdGF0ZSBzZXNzaW9uID0gYXN5bmNTZXNzaW9uLnZhbHVlID8/IGNvbnN0IFNlc3Npb25Vbmtub3duKCk7CiAgICBmaW5hbCBib29sIGluRmxpZ2h0ID0KICAgICAgICBhc3luY1Nlc3Npb24uaXNMb2FkaW5nIHx8IHNlc3Npb24gaXMgU2Vzc2lvbkF1dGhlbnRpY2F0aW5nOwogICAgZmluYWwgQXBwRXJyb3I/IGZhaWx1cmUgPSBzZXNzaW9uIGlzIFNlc3Npb25GYWlsZWQgPyBzZXNzaW9uLmVycm9yIDogbnVsbDsKCiAgICBmaW5hbCBBcHBUb2tlbnMgdG9rZW5zID0gY29udGV4dC50b2tlbnM7CiAgICBmaW5hbCBUZXh0VGhlbWUgdGV4dCA9IGNvbnRleHQudGV4dDsKICAgIGZpbmFsIEFwcExvY2FsaXphdGlvbnMgbDEwbiA9IEFwcExvY2FsaXphdGlvbnMub2YoY29udGV4dCk7CgogICAgcmV0dXJuIFNjYWZmb2xkKAogICAgICBiYWNrZ3JvdW5kQ29sb3I6IHRva2Vucy5iYWNrZ3JvdW5kLAogICAgICBib2R5OiBEZWNvcmF0ZWRCb3goCiAgICAgICAgZGVjb3JhdGlvbjogQm94RGVjb3JhdGlvbihncmFkaWVudDogdG9rZW5zLmJhY2tncm91bmRHcmFkaWVudCksCiAgICAgICAgY2hpbGQ6IFNhZmVBcmVhKAogICAgICAgICAgY2hpbGQ6IENlbnRlcigKICAgICAgICAgICAgY2hpbGQ6IFNpbmdsZUNoaWxkU2Nyb2xsVmlldygKICAgICAgICAgICAgICBwYWRkaW5nOiBjb25zdCBFZGdlSW5zZXRzLnN5bW1ldHJpYygKICAgICAgICAgICAgICAgIGhvcml6b250YWw6IEFwcFNwYWNpbmcueGwsCiAgICAgICAgICAgICAgICB2ZXJ0aWNhbDogQXBwU3BhY2luZy54eGwsCiAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICBjaGlsZDogQ29uc3RyYWluZWRCb3goCiAgICAgICAgICAgICAgICBjb25zdHJhaW50czogY29uc3QgQm94Q29uc3RyYWludHMoCiAgICAgICAgICAgICAgICAgIG1heFdpZHRoOiBBcHBTaXplcy5tYXhGb3JtV2lkdGgsCiAgICAgICAgICAgICAgICApLAogICAgICAgICAgICAgICAgY2hpbGQ6IENvbHVtbigKICAgICAgICAgICAgICAgICAgbWFpbkF4aXNTaXplOiBNYWluQXhpc1NpemUubWluLAogICAgICAgICAgICAgICAgICBjaGlsZHJlbjogWwogICAgICAgICAgICAgICAgICAgIGNvbnN0IF9IZWFkZXIoKSwKICAgICAgICAgICAgICAgICAgICBjb25zdCBTaXplZEJveChoZWlnaHQ6IEFwcFNwYWNpbmcueHhsKSwKICAgICAgICAgICAgICAgICAgICBDb250YWluZXIoCiAgICAgICAgICAgICAgICAgICAgICBwYWRkaW5nOiBjb25zdCBFZGdlSW5zZXRzLmFsbChBcHBTcGFjaW5nLnhsKSwKICAgICAgICAgICAgICAgICAgICAgIGRlY29yYXRpb246IEJveERlY29yYXRpb24oCiAgICAgICAgICAgICAgICAgICAgICAgIGNvbG9yOiB0b2tlbnMuc3VyZmFjZSwKICAgICAgICAgICAgICAgICAgICAgICAgYm9yZGVyUmFkaXVzOiBBcHBSYWRpdXMuYnJYeGwsCiAgICAgICAgICAgICAgICAgICAgICAgIGJvcmRlcjogQm9yZGVyLmFsbChjb2xvcjogdG9rZW5zLmJvcmRlciksCiAgICAgICAgICAgICAgICAgICAgICAgIGJveFNoYWRvdzogdG9rZW5zLnNoYWRvd0xnLAogICAgICAgICAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICAgICAgICAgIGNoaWxkOiBGb3JtKAogICAgICAgICAgICAgICAgICAgICAgICBrZXk6IF9mb3JtS2V5LAogICAgICAgICAgICAgICAgICAgICAgICBjaGlsZDogQ29sdW1uKAogICAgICAgICAgICAgICAgICAgICAgICAgIGNyb3NzQXhpc0FsaWdubWVudDogQ3Jvc3NBeGlzQWxpZ25tZW50LnN0cmV0Y2gsCiAgICAgICAgICAgICAgICAgICAgICAgICAgY2hpbGRyZW46IFsKICAgICAgICAgICAgICAgICAgICAgICAgICAgIF9BdXRoTW9kZVRhYnMoCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlzUmVnaXN0ZXI6IF9pc1JlZ2lzdGVyLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBlbmFibGVkOiAhaW5GbGlnaHQsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIG9uQ2hhbmdlZDogX3NldE1vZGUsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICApLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgY29uc3QgU2l6ZWRCb3goaGVpZ2h0OiBBcHBTcGFjaW5nLnhsKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgIFRleHQoCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIF9pc1JlZ2lzdGVyID8gbDEwbi5jcmVhdGVBY2NvdW50IDogbDEwbi5zaWduSW4sCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGtleTogY29uc3QgS2V5KCdzaWduSW4udGl0bGUnKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGV4dEFsaWduOiBUZXh0QWxpZ24uY2VudGVyLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdHlsZTogdGV4dC5oZWFkbGluZVNtYWxsPy5jb3B5V2l0aCgKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb2xvcjogdG9rZW5zLnRleHRQcmltYXJ5LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGZvbnRXZWlnaHQ6IEZvbnRXZWlnaHQuYm9sZCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBTaXplZEJveChoZWlnaHQ6IEFwcFNwYWNpbmcuc20pLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgVGV4dCgKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgX2lzUmVnaXN0ZXIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgID8gbDEwbi5zaWduVXBTdWJ0aXRsZQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBsMTBuLnNpZ25JblN1YnRpdGxlLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICB0ZXh0QWxpZ246IFRleHRBbGlnbi5jZW50ZXIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHN0eWxlOiB0ZXh0LmJvZHlNZWRpdW0/LmNvcHlXaXRoKAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNvbG9yOiB0b2tlbnMudGV4dFNlY29uZGFyeSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBTaXplZEJveChoZWlnaHQ6IEFwcFNwYWNpbmcueGwpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKF9pc1JlZ2lzdGVyKSAuLi5bCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNvbnN0IF9SdWxlc0JveCgpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBTaXplZEJveChoZWlnaHQ6IEFwcFNwYWNpbmcueGwpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgXSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmIChmYWlsdXJlICE9IG51bGwpIC4uLlsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgX0Vycm9yQmFubmVyKAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGtleTogY29uc3QgS2V5KCdzaWduSW4uZXJyb3JCYW5uZXInKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBtZXNzYWdlOiBFcnJvclByZXNlbnRlci5tZXNzYWdlKGZhaWx1cmUpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICApLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBTaXplZEJveChoZWlnaHQ6IEFwcFNwYWNpbmcubGcpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgXSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgIEFwcFRleHRGaWVsZCgKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZmllbGRLZXk6IGNvbnN0IEtleSgnc2lnbkluLmVtYWlsRmllbGQnKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY29udHJvbGxlcjogX2VtYWlsQ29udHJvbGxlciwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgZW5hYmxlZDogIWluRmxpZ2h0LAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBsYWJlbDogbDEwbi5lbWFpbCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaGludDogbDEwbi5lbWFpbEhpbnQsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHByZWZpeEljb246IEljb25zLm1haWxfb3V0bGluZSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAga2V5Ym9hcmRUeXBlOiBUZXh0SW5wdXRUeXBlLmVtYWlsQWRkcmVzcywKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGV4dElucHV0QWN0aW9uOiBUZXh0SW5wdXRBY3Rpb24ubmV4dCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYXV0b2ZpbGxIaW50czogY29uc3QgW0F1dG9maWxsSGludHMuZW1haWxdLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICB2YWxpZGF0b3I6IChTdHJpbmc/IHZhbHVlKSA9PgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKHZhbHVlID09IG51bGwgfHwgdmFsdWUudHJpbSgpLmlzRW1wdHkpCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA/IGwxMG4uZW1haWxSZXF1aXJlZAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBudWxsLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNvbnN0IFNpemVkQm94KGhlaWdodDogQXBwU3BhY2luZy5sZyksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICBBcHBUZXh0RmllbGQoCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGZpZWxkS2V5OiBjb25zdCBLZXkoJ3NpZ25Jbi5wYXNzd29yZEZpZWxkJyksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNvbnRyb2xsZXI6IF9wYXNzd29yZENvbnRyb2xsZXIsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGVuYWJsZWQ6ICFpbkZsaWdodCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgb2JzY3VyZTogdHJ1ZSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgbGFiZWw6IGwxMG4ucGFzc3dvcmQsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHByZWZpeEljb246IEljb25zLmxvY2tfb3V0bGluZSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgdGV4dElucHV0QWN0aW9uOiBfaXNSZWdpc3RlcgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPyBUZXh0SW5wdXRBY3Rpb24ubmV4dAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgOiBUZXh0SW5wdXRBY3Rpb24uZG9uZSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYXV0b2ZpbGxIaW50czogWwogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIF9pc1JlZ2lzdGVyCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgID8gQXV0b2ZpbGxIaW50cy5uZXdQYXNzd29yZAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IEF1dG9maWxsSGludHMucGFzc3dvcmQsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIF0sCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIG9uRmllbGRTdWJtaXR0ZWQ6IF9pc1JlZ2lzdGVyCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA/IG51bGwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDogKF8pID0+IF9zdWJtaXQoc2Vzc2lvbiksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHZhbGlkYXRvcjogKFN0cmluZz8gdmFsdWUpID0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAodmFsdWUgPT0gbnVsbCB8fCB2YWx1ZS50cmltKCkuaXNFbXB0eSkKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgID8gbDEwbi5wYXNzd29yZFJlcXVpcmVkCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IG51bGwsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICApLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKF9pc1JlZ2lzdGVyKSAuLi5bCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGNvbnN0IFNpemVkQm94KGhlaWdodDogQXBwU3BhY2luZy5sZyksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEFwcFRleHRGaWVsZCgKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBmaWVsZEtleTogY29uc3QgS2V5KAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgJ3NpZ25Jbi5jb25maXJtUGFzc3dvcmRGaWVsZCcsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb250cm9sbGVyOiBfY29uZmlybVBhc3N3b3JkQ29udHJvbGxlciwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBlbmFibGVkOiAhaW5GbGlnaHQsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgb2JzY3VyZTogdHJ1ZSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBsYWJlbDogbDEwbi5jb25maXJtUGFzc3dvcmQsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcHJlZml4SWNvbjogSWNvbnMubG9ja19vdXRsaW5lLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHRleHRJbnB1dEFjdGlvbjogVGV4dElucHV0QWN0aW9uLmRvbmUsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgYXV0b2ZpbGxIaW50czogY29uc3QgWwogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQXV0b2ZpbGxIaW50cy5uZXdQYXNzd29yZCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBdLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIG9uRmllbGRTdWJtaXR0ZWQ6IChfKSA9PiBfc3VibWl0KHNlc3Npb24pLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHZhbGlkYXRvcjogKFN0cmluZz8gdmFsdWUpIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmICh2YWx1ZSA9PSBudWxsIHx8IHZhbHVlLnRyaW0oKS5pc0VtcHR5KSB7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIHJldHVybiBsMTBuLmNvbmZpcm1QYXNzd29yZFJlcXVpcmVkOwogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKHZhbHVlICE9IF9wYXNzd29yZENvbnRyb2xsZXIudGV4dCkgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICByZXR1cm4gbDEwbi5wYXNzd29yZE1pc21hdGNoOwogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcmV0dXJuIG51bGw7CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICAgICAgICAgICAgICAgIF0sCiAgICAgICAgICAgICAgICAgICAgICAgICAgICBjb25zdCBTaXplZEJveChoZWlnaHQ6IEFwcFNwYWNpbmcueGwpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgQXBwQnV0dG9uKAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBrZXk6IGNvbnN0IEtleSgnc2lnbkluLnN1Ym1pdCcpLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBsYWJlbDogX2lzUmVnaXN0ZXIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgID8gbDEwbi5jcmVhdGVBY2NvdW50CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6IGwxMG4uc2lnbkluLAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICBsb2FkaW5nOiBpbkZsaWdodCwKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgb25QcmVzc2VkOiBpbkZsaWdodAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPyBudWxsCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA6ICgpID0+IF9zdWJtaXQoc2Vzc2lvbiksCiAgICAgICAgICAgICAgICAgICAgICAgICAgICApLAogICAgICAgICAgICAgICAgICAgICAgICAgIF0sCiAgICAgICAgICAgICAgICAgICAgICAgICksCiAgICAgICAgICAgICAgICAgICAgICApLAogICAgICAgICAgICAgICAgICAgICksCiAgICAgICAgICAgICAgICAgIF0sCiAgICAgICAgICAgICAgICApLAogICAgICAgICAgICAgICksCiAgICAgICAgICAgICksCiAgICAgICAgICApLAogICAgICAgICksCiAgICAgICksCiAgICApOwogIH0KfQoKLy8vIFNlZ21lbnRlZCDYr9iu2YjZhC/Yqtiz2KzZitmEIHN3aXRjaGVyIHJlcGxhY2luZyB0aGUgb2xkIGxpbmstc3R5bGUgdG9nZ2xlIGJ1dHRvbi4KLy8vIFBvcnRlZCBmcm9tIHRoZSBsZWdhY3kgYC5hdXRoLXRhYnNgIG1hcmt1cDsgY29sb3JzIGNvbWUgZW50aXJlbHkgZnJvbQovLy8gW0FwcFRva2Vuc10gc28gdGhlIG5ldyBhcHAncyBwYWxldHRlIGlzIHVuYWZmZWN0ZWQuCmNsYXNzIF9BdXRoTW9kZVRhYnMgZXh0ZW5kcyBTdGF0ZWxlc3NXaWRnZXQgewogIGNvbnN0IF9BdXRoTW9kZVRhYnMoewogICAgcmVxdWlyZWQgdGhpcy5pc1JlZ2lzdGVyLAogICAgcmVxdWlyZWQgdGhpcy5lbmFibGVkLAogICAgcmVxdWlyZWQgdGhpcy5vbkNoYW5nZWQsCiAgfSk7CgogIGZpbmFsIGJvb2wgaXNSZWdpc3RlcjsKICBmaW5hbCBib29sIGVuYWJsZWQ7CiAgZmluYWwgVmFsdWVDaGFuZ2VkPGJvb2w+IG9uQ2hhbmdlZDsKCiAgQG92ZXJyaWRlCiAgV2lkZ2V0IGJ1aWxkKEJ1aWxkQ29udGV4dCBjb250ZXh0KSB7CiAgICBmaW5hbCBBcHBUb2tlbnMgdG9rZW5zID0gY29udGV4dC50b2tlbnM7CiAgICByZXR1cm4gQ29udGFpbmVyKAogICAgICBoZWlnaHQ6IEFwcFNpemVzLmNvbnRyb2xNZCwKICAgICAgcGFkZGluZzogY29uc3QgRWRnZUluc2V0cy5hbGwoQXBwU3BhY2luZy54cyAvIDIpLAogICAgICBkZWNvcmF0aW9uOiBCb3hEZWNvcmF0aW9uKAogICAgICAgIGNvbG9yOiB0b2tlbnMuc3VyZmFjZUVsZXZhdGVkLAogICAgICAgIGJvcmRlclJhZGl1czogQXBwUmFkaXVzLmJyTWQsCiAgICAgICAgYm9yZGVyOiBCb3JkZXIuYWxsKGNvbG9yOiB0b2tlbnMuYm9yZGVyKSwKICAgICAgKSwKICAgICAgY2hpbGQ6IFJvdygKICAgICAgICBjaGlsZHJlbjogWwogICAgICAgICAgRXhwYW5kZWQoCiAgICAgICAgICAgIGNoaWxkOiBfQXV0aE1vZGVUYWIoCiAgICAgICAgICAgICAgZmllbGRLZXk6IGNvbnN0IEtleSgnc2lnbkluLnRhYkxvZ2luJyksCiAgICAgICAgICAgICAgbGFiZWw6IEFwcExvY2FsaXphdGlvbnMub2YoY29udGV4dCkuYXV0aFRhYlNpZ25JbiwKICAgICAgICAgICAgICBzZWxlY3RlZDogIWlzUmVnaXN0ZXIsCiAgICAgICAgICAgICAgZW5hYmxlZDogZW5hYmxlZCwKICAgICAgICAgICAgICBvblRhcDogKCkgPT4gb25DaGFuZ2VkKGZhbHNlKSwKICAgICAgICAgICAgKSwKICAgICAgICAgICksCiAgICAgICAgICBFeHBhbmRlZCgKICAgICAgICAgICAgY2hpbGQ6IF9BdXRoTW9kZVRhYigKICAgICAgICAgICAgICBmaWVsZEtleTogY29uc3QgS2V5KCdzaWduSW4udGFiUmVnaXN0ZXInKSwKICAgICAgICAgICAgICBsYWJlbDogQXBwTG9jYWxpemF0aW9ucy5vZihjb250ZXh0KS5hdXRoVGFiUmVnaXN0ZXIsCiAgICAgICAgICAgICAgc2VsZWN0ZWQ6IGlzUmVnaXN0ZXIsCiAgICAgICAgICAgICAgZW5hYmxlZDogZW5hYmxlZCwKICAgICAgICAgICAgICBvblRhcDogKCkgPT4gb25DaGFuZ2VkKHRydWUpLAogICAgICAgICAgICApLAogICAgICAgICAgKSwKICAgICAgICBdLAogICAgICApLAogICAgKTsKICB9Cn0KCmNsYXNzIF9BdXRoTW9kZVRhYiBleHRlbmRzIFN0YXRlbGVzc1dpZGdldCB7CiAgY29uc3QgX0F1dGhNb2RlVGFiKHsKICAgIHJlcXVpcmVkIHRoaXMuZmllbGRLZXksCiAgICByZXF1aXJlZCB0aGlzLmxhYmVsLAogICAgcmVxdWlyZWQgdGhpcy5zZWxlY3RlZCwKICAgIHJlcXVpcmVkIHRoaXMuZW5hYmxlZCwKICAgIHJlcXVpcmVkIHRoaXMub25UYXAsCiAgfSk7CgogIGZpbmFsIEtleSBmaWVsZEtleTsKICBmaW5hbCBTdHJpbmcgbGFiZWw7CiAgZmluYWwgYm9vbCBzZWxlY3RlZDsKICBmaW5hbCBib29sIGVuYWJsZWQ7CiAgZmluYWwgVm9pZENhbGxiYWNrIG9uVGFwOwoKICBAb3ZlcnJpZGUKICBXaWRnZXQgYnVpbGQoQnVpbGRDb250ZXh0IGNvbnRleHQpIHsKICAgIGZpbmFsIEFwcFRva2VucyB0b2tlbnMgPSBjb250ZXh0LnRva2VuczsKICAgIGZpbmFsIFRleHRUaGVtZSB0ZXh0ID0gY29udGV4dC50ZXh0OwogICAgcmV0dXJuIE1hdGVyaWFsKAogICAgICBrZXk6IGZpZWxkS2V5LAogICAgICBjb2xvcjogQ29sb3JzLnRyYW5zcGFyZW50LAogICAgICBjaGlsZDogSW5rV2VsbCgKICAgICAgICBib3JkZXJSYWRpdXM6IEFwcFJhZGl1cy5iclNtLAogICAgICAgIG9uVGFwOiBlbmFibGVkID8gb25UYXAgOiBudWxsLAogICAgICAgIGNoaWxkOiBBbmltYXRlZENvbnRhaW5lcigKICAgICAgICAgIGR1cmF0aW9uOiBBcHBNb3Rpb24udGFiU3dpdGNoLAogICAgICAgICAgY3VydmU6IEFwcE1vdGlvbi5zdGFuZGFyZEN1cnZlLAogICAgICAgICAgYWxpZ25tZW50OiBBbGlnbm1lbnQuY2VudGVyLAogICAgICAgICAgZGVjb3JhdGlvbjogQm94RGVjb3JhdGlvbigKICAgICAgICAgICAgY29sb3I6IHNlbGVjdGVkID8gdG9rZW5zLnByaW1hcnkgOiBDb2xvcnMudHJhbnNwYXJlbnQsCiAgICAgICAgICAgIGJvcmRlclJhZGl1czogQXBwUmFkaXVzLmJyU20sCiAgICAgICAgICApLAogICAgICAgICAgY2hpbGQ6IFRleHQoCiAgICAgICAgICAgIGxhYmVsLAogICAgICAgICAgICBzdHlsZTogdGV4dC5sYWJlbExhcmdlPy5jb3B5V2l0aCgKICAgICAgICAgICAgICBjb2xvcjogc2VsZWN0ZWQgPyB0b2tlbnMub25QcmltYXJ5IDogdG9rZW5zLnRleHRTZWNvbmRhcnksCiAgICAgICAgICAgICAgZm9udFdlaWdodDogRm9udFdlaWdodC53NjAwLAogICAgICAgICAgICApLAogICAgICAgICAgKSwKICAgICAgICApLAogICAgICApLAogICAgKTsKICB9Cn0KCi8vLyAi2YPZitmBINiq2YTYudio2J8iIGV4cGxhaW5lciBzaG93biBvbiB0aGUgcmVnaXN0ZXIgdGFiIOKAlCBwb3J0ZWQgZnJvbSB0aGUgbGVnYWN5Ci8vLyBgLnJ1bGVzLWJveGAgbWFya3VwIHdpdGggdGhlIHBsYXRmb3JtJ3MgY3VycmVudCBzY29yaW5nIGNvcHkuCmNsYXNzIF9SdWxlc0JveCBleHRlbmRzIFN0YXRlbGVzc1dpZGdldCB7CiAgY29uc3QgX1J1bGVzQm94KCk7CgogIEBvdmVycmlkZQogIFdpZGdldCBidWlsZChCdWlsZENvbnRleHQgY29udGV4dCkgewogICAgZmluYWwgQXBwVG9rZW5zIHRva2VucyA9IGNvbnRleHQudG9rZW5zOwogICAgZmluYWwgVGV4dFRoZW1lIHRleHQgPSBjb250ZXh0LnRleHQ7CiAgICBmaW5hbCBBcHBMb2NhbGl6YXRpb25zIGwxMG4gPSBBcHBMb2NhbGl6YXRpb25zLm9mKGNvbnRleHQpOwoKICAgIHJldHVybiBDb250YWluZXIoCiAgICAgIHBhZGRpbmc6IGNvbnN0IEVkZ2VJbnNldHMuYWxsKEFwcFNwYWNpbmcubGcpLAogICAgICBkZWNvcmF0aW9uOiBCb3hEZWNvcmF0aW9uKAogICAgICAgIGNvbG9yOiB0b2tlbnMuc3VyZmFjZUVsZXZhdGVkLAogICAgICAgIGJvcmRlclJhZGl1czogQXBwUmFkaXVzLmJyTGcsCiAgICAgICAgYm9yZGVyOiBCb3JkZXIuYWxsKGNvbG9yOiB0b2tlbnMuYm9yZGVyKSwKICAgICAgKSwKICAgICAgY2hpbGQ6IENvbHVtbigKICAgICAgICBjcm9zc0F4aXNBbGlnbm1lbnQ6IENyb3NzQXhpc0FsaWdubWVudC5zdGFydCwKICAgICAgICBjaGlsZHJlbjogWwogICAgICAgICAgUm93KAogICAgICAgICAgICBjaGlsZHJlbjogWwogICAgICAgICAgICAgIEljb24oCiAgICAgICAgICAgICAgICBJY29ucy5jaGVja2xpc3RfcnRsX3JvdW5kZWQsCiAgICAgICAgICAgICAgICBzaXplOiBBcHBTaXplcy5pY29uTWQsCiAgICAgICAgICAgICAgICBjb2xvcjogdG9rZW5zLnRleHRQcmltYXJ5LAogICAgICAgICAgICAgICksCiAgICAgICAgICAgICAgY29uc3QgU2l6ZWRCb3god2lkdGg6IEFwcFNwYWNpbmcuc20pLAogICAgICAgICAgICAgIFRleHQoCiAgICAgICAgICAgICAgICBsMTBuLnJ1bGVzVGl0bGUsCiAgICAgICAgICAgICAgICBzdHlsZTogdGV4dC50aXRsZVNtYWxsPy5jb3B5V2l0aCgKICAgICAgICAgICAgICAgICAgY29sb3I6IHRva2Vucy50ZXh0UHJpbWFyeSwKICAgICAgICAgICAgICAgICAgZm9udFdlaWdodDogRm9udFdlaWdodC5ib2xkLAogICAgICAgICAgICAgICAgKSwKICAgICAgICAgICAgICApLAogICAgICAgICAgICBdLAogICAgICAgICAgKSwKICAgICAgICAgIGNvbnN0IFNpemVkQm94KGhlaWdodDogQXBwU3BhY2luZy54cyksCiAgICAgICAgICBUZXh0KAogICAgICAgICAgICBsMTBuLnJ1bGVzVGFnbGluZSwKICAgICAgICAgICAgc3R5bGU6IHRleHQuYm9keVNtYWxsPy5jb3B5V2l0aChjb2xvcjogdG9rZW5zLnRleHRNdXRlZCksCiAgICAgICAgICApLAogICAgICAgICAgY29uc3QgU2l6ZWRCb3goaGVpZ2h0OiBBcHBTcGFjaW5nLm1kKSwKICAgICAgICAgIF9SdWxlSXRlbSgKICAgICAgICAgICAgaWNvbjogSWNvbnMuc3BvcnRzX3NvY2Nlcl9yb3VuZGVkLAogICAgICAgICAgICBpY29uQ29sb3I6IHRva2Vucy50ZXh0U2Vjb25kYXJ5LAogICAgICAgICAgICBsYWJlbDogbDEwbi5ydWxlc1ByZWRpY3RNYWpvckxlYWd1ZXMsCiAgICAgICAgICApLAogICAgICAgICAgY29uc3QgU2l6ZWRCb3goaGVpZ2h0OiBBcHBTcGFjaW5nLnNtKSwKICAgICAgICAgIF9SdWxlSXRlbSgKICAgICAgICAgICAgaWNvbjogSWNvbnMuY2hlY2tfY2lyY2xlX3JvdW5kZWQsCiAgICAgICAgICAgIGljb25Db2xvcjogdG9rZW5zLnByaW1hcnksCiAgICAgICAgICAgIGxhYmVsOiBsMTBuLnJ1bGVzQ29ycmVjdFByZWRpY3Rpb24sCiAgICAgICAgICApLAogICAgICAgICAgY29uc3QgU2l6ZWRCb3goaGVpZ2h0OiBBcHBTcGFjaW5nLnNtKSwKICAgICAgICAgIF9SdWxlSXRlbSgKICAgICAgICAgICAgaWNvbjogSWNvbnMuY2FuY2VsX3JvdW5kZWQsCiAgICAgICAgICAgIGljb25Db2xvcjogdG9rZW5zLnRleHRNdXRlZCwKICAgICAgICAgICAgbGFiZWw6IGwxMG4ucnVsZXNXcm9uZ1ByZWRpY3Rpb24sCiAgICAgICAgICApLAogICAgICAgICAgY29uc3QgU2l6ZWRCb3goaGVpZ2h0OiBBcHBTcGFjaW5nLnNtKSwKICAgICAgICAgIF9SdWxlSXRlbSgKICAgICAgICAgICAgaWNvbjogSWNvbnMuc3Rhcl9yb3VuZGVkLAogICAgICAgICAgICBpY29uQ29sb3I6IHRva2Vucy5nb2xkLAogICAgICAgICAgICBsYWJlbDogbDEwbi5ydWxlc0RvdWJsZU1hdGNoLAogICAgICAgICAgKSwKICAgICAgICBdLAogICAgICApLAogICAgKTsKICB9Cn0KCmNsYXNzIF9SdWxlSXRlbSBleHRlbmRzIFN0YXRlbGVzc1dpZGdldCB7CiAgY29uc3QgX1J1bGVJdGVtKHsKICAgIHJlcXVpcmVkIHRoaXMuaWNvbiwKICAgIHJlcXVpcmVkIHRoaXMuaWNvbkNvbG9yLAogICAgcmVxdWlyZWQgdGhpcy5sYWJlbCwKICB9KTsKCiAgZmluYWwgSWNvbkRhdGEgaWNvbjsKICBmaW5hbCBDb2xvciBpY29uQ29sb3I7CiAgZmluYWwgU3RyaW5nIGxhYmVsOwoKICBAb3ZlcnJpZGUKICBXaWRnZXQgYnVpbGQoQnVpbGRDb250ZXh0IGNvbnRleHQpIHsKICAgIGZpbmFsIEFwcFRva2VucyB0b2tlbnMgPSBjb250ZXh0LnRva2VuczsKICAgIGZpbmFsIFRleHRUaGVtZSB0ZXh0ID0gY29udGV4dC50ZXh0OwogICAgcmV0dXJuIFJvdygKICAgICAgY3Jvc3NBeGlzQWxpZ25tZW50OiBDcm9zc0F4aXNBbGlnbm1lbnQuc3RhcnQsCiAgICAgIGNoaWxkcmVuOiBbCiAgICAgICAgSWNvbihpY29uLCBzaXplOiBBcHBTaXplcy5pY29uU20sIGNvbG9yOiBpY29uQ29sb3IpLAogICAgICAgIGNvbnN0IFNpemVkQm94KHdpZHRoOiBBcHBTcGFjaW5nLnNtKSwKICAgICAgICBFeHBhbmRlZCgKICAgICAgICAgIGNoaWxkOiBUZXh0KAogICAgICAgICAgICBsYWJlbCwKICAgICAgICAgICAgc3R5bGU6IHRleHQuYm9keVNtYWxsPy5jb3B5V2l0aChjb2xvcjogdG9rZW5zLnRleHRTZWNvbmRhcnkpLAogICAgICAgICAgKSwKICAgICAgICApLAogICAgICBdLAogICAgKTsKICB9Cn0KCmNsYXNzIF9IZWFkZXIgZXh0ZW5kcyBTdGF0ZWxlc3NXaWRnZXQgewogIGNvbnN0IF9IZWFkZXIoKTsKCiAgQG92ZXJyaWRlCiAgV2lkZ2V0IGJ1aWxkKEJ1aWxkQ29udGV4dCBjb250ZXh0KSB7CiAgICBmaW5hbCBBcHBUb2tlbnMgdG9rZW5zID0gY29udGV4dC50b2tlbnM7CiAgICBmaW5hbCBUZXh0VGhlbWUgdGV4dCA9IGNvbnRleHQudGV4dDsKICAgIGZpbmFsIEFwcExvY2FsaXphdGlvbnMgbDEwbiA9IEFwcExvY2FsaXphdGlvbnMub2YoY29udGV4dCk7CiAgICByZXR1cm4gQ29sdW1uKAogICAgICBjaGlsZHJlbjogWwogICAgICAgIENvbnRhaW5lcigKICAgICAgICAgIGhlaWdodDogQXBwU2l6ZXMuYnJhbmRNYXJrLAogICAgICAgICAgd2lkdGg6IEFwcFNpemVzLmJyYW5kTWFyaywKICAgICAgICAgIGRlY29yYXRpb246IEJveERlY29yYXRpb24oCiAgICAgICAgICAgIGdyYWRpZW50OiB0b2tlbnMucHJpbWFyeUdyYWRpZW50LAogICAgICAgICAgICBib3JkZXJSYWRpdXM6IEFwcFJhZGl1cy5iclhsLAogICAgICAgICAgICBib3hTaGFkb3c6IHRva2Vucy5zaGFkb3dNZCwKICAgICAgICAgICksCiAgICAgICAgICBjaGlsZDogSWNvbigKICAgICAgICAgICAgSWNvbnMuc3BvcnRzX3NvY2Nlcl9yb3VuZGVkLAogICAgICAgICAgICBjb2xvcjogdG9rZW5zLm9uUHJpbWFyeSwKICAgICAgICAgICAgc2l6ZTogQXBwU2l6ZXMuaWNvblhsLAogICAgICAgICAgKSwKICAgICAgICApLAogICAgICAgIGNvbnN0IFNpemVkQm94KGhlaWdodDogQXBwU3BhY2luZy5sZyksCiAgICAgICAgVGV4dCgKICAgICAgICAgIGwxMG4uYXBwVGl0bGUsCiAgICAgICAgICBzdHlsZTogdGV4dC5oZWFkbGluZU1lZGl1bT8uY29weVdpdGgoCiAgICAgICAgICAgIGNvbG9yOiB0b2tlbnMudGV4dFByaW1hcnksCiAgICAgICAgICAgIGZvbnRXZWlnaHQ6IEZvbnRXZWlnaHQuYm9sZCwKICAgICAgICAgICksCiAgICAgICAgKSwKICAgICAgICBjb25zdCBTaXplZEJveChoZWlnaHQ6IEFwcFNwYWNpbmcueHMpLAogICAgICAgIFRleHQoCiAgICAgICAgICBsMTBuLnRhZ2xpbmUsCiAgICAgICAgICBzdHlsZTogdGV4dC5ib2R5U21hbGw/LmNvcHlXaXRoKGNvbG9yOiB0b2tlbnMudGV4dE11dGVkKSwKICAgICAgICApLAogICAgICBdLAogICAgKTsKICB9Cn0KCmNsYXNzIF9FcnJvckJhbm5lciBleHRlbmRzIFN0YXRlbGVzc1dpZGdldCB7CiAgY29uc3QgX0Vycm9yQmFubmVyKHtzdXBlci5rZXksIHJlcXVpcmVkIHRoaXMubWVzc2FnZX0pOwogIGZpbmFsIFN0cmluZyBtZXNzYWdlOwoKICBAb3ZlcnJpZGUKICBXaWRnZXQgYnVpbGQoQnVpbGRDb250ZXh0IGNvbnRleHQpIHsKICAgIGZpbmFsIEFwcFRva2VucyB0b2tlbnMgPSBjb250ZXh0LnRva2VuczsKICAgIGZpbmFsIFRleHRUaGVtZSB0ZXh0ID0gY29udGV4dC50ZXh0OwogICAgcmV0dXJuIENvbnRhaW5lcigKICAgICAgcGFkZGluZzogY29uc3QgRWRnZUluc2V0cy5hbGwoQXBwU3BhY2luZy5tZCksCiAgICAgIGRlY29yYXRpb246IEJveERlY29yYXRpb24oCiAgICAgICAgY29sb3I6IHRva2Vucy5lcnJvckNvbnRhaW5lciwKICAgICAgICBib3JkZXJSYWRpdXM6IEFwcFJhZGl1cy5ick1kLAogICAgICAgIGJvcmRlcjogQm9yZGVyLmFsbChjb2xvcjogdG9rZW5zLmVycm9yLndpdGhWYWx1ZXMoYWxwaGE6IDAuNCkpLAogICAgICApLAogICAgICBjaGlsZDogUm93KAogICAgICAgIGNyb3NzQXhpc0FsaWdubWVudDogQ3Jvc3NBeGlzQWxpZ25tZW50LnN0YXJ0LAogICAgICAgIGNoaWxkcmVuOiBbCiAgICAgICAgICBJY29uKAogICAgICAgICAgICBJY29ucy5lcnJvcl9vdXRsaW5lX3JvdW5kZWQsCiAgICAgICAgICAgIGNvbG9yOiB0b2tlbnMuZXJyb3IsCiAgICAgICAgICAgIHNpemU6IEFwcFNpemVzLmljb25NZCwKICAgICAgICAgICksCiAgICAgICAgICBjb25zdCBTaXplZEJveCh3aWR0aDogQXBwU3BhY2luZy5zbSksCiAgICAgICAgICBFeHBhbmRlZCgKICAgICAgICAgICAgY2hpbGQ6IFRleHQoCiAgICAgICAgICAgICAgbWVzc2FnZSwKICAgICAgICAgICAgICBzdHlsZTogdGV4dC5ib2R5U21hbGw/LmNvcHlXaXRoKGNvbG9yOiB0b2tlbnMudGV4dFByaW1hcnkpLAogICAgICAgICAgICApLAogICAgICAgICAgKSwKICAgICAgICBdLAogICAgICApLAogICAgKTsKICB9Cn0K"


def apply_str_replace_edits() -> list[str]:
    failures = []
    for path, replacements in EDITS.items():
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
        except FileNotFoundError:
            failures.append(f"XX: الملف غير موجود: {path}")
            continue

        original = content
        for old, new in replacements:
            count = content.count(old)
            if count != 1:
                failures.append(
                    f"XX: {path}: تطابق={count} (متوقع 1) لهذا المقطع:\n"
                    f"{old[:120]!r}..."
                )
                continue
            content = content.replace(old, new)

        if content == original:
            continue

        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"OK: {path}")

    return failures


def apply_sign_in_screen() -> list[str]:
    try:
        with open(SIGN_IN_SCREEN_PATH, "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        return [f"XX: الملف غير موجود: {SIGN_IN_SCREEN_PATH}"]

    if SIGN_IN_SCREEN_MARKER not in content:
        return [
            f"XX: {SIGN_IN_SCREEN_PATH}: العلامة المتوقعة غير موجودة "
            f"({SIGN_IN_SCREEN_MARKER!r}) — الملف قد يكون مُعدَّلاً مسبقاً، "
            "لم تتم الكتابة."
        ]

    new_content = base64.b64decode(SIGN_IN_SCREEN_NEW_B64).decode("utf-8")
    with open(SIGN_IN_SCREEN_PATH, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"OK: {SIGN_IN_SCREEN_PATH} ({len(new_content)} حرف)")
    return []


def main() -> int:
    failures = apply_str_replace_edits()
    failures += apply_sign_in_screen()

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1

    print("OK: كل الملفات (6) عُدِّلت بنجاح.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
