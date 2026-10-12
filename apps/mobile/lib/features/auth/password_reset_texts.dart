/// The words of the in-app password reset by e-mailed code (batch 110).
///
/// The reset e-mail carries a code; the player types it here instead of
/// opening the e-mail's link, which landed on the web build. The server
/// decides whether a code is right; these only say, in Arabic, what to do.
library;

/// The request step's line under the title.
const String resetCodeRequestSubtitle =
    'اكتب بريدك الإلكتروني وسنرسل لك رمزًا من 6 أرقام لتغيير كلمة المرور داخل التطبيق.';

/// The request step's button.
const String resetCodeSendLabel = 'إرسال الرمز';

/// What the player reads once the code was asked for [email].
String resetCodeSentMessage(String email) =>
    'إذا كان البريد $email مرتبطًا بحساب، فسيصلك رمز من 6 أرقام. اكتبه هنا. '
    'لا تجده؟ افحص مجلد الرسائل غير المرغوبة (Spam).';

/// The code field's label.
const String resetCodeFieldLabel = 'رمز التحقق';

/// The code field's hint.
const String resetCodeFieldHint = '123456';

/// The code field's refusal when it is not 6 to 10 digits.
const String resetCodeFormatError = 'اكتب الرمز كما وصلك في البريد (6 أرقام).';

/// The button that checks the code.
const String resetCodeVerifyLabel = 'تأكيد الرمز';

/// The button that sends a new code.
const String resetCodeResendLabel = 'أرسل الرمز مرة أخرى';

/// The same button while the e-mail service still refuses a new code.
const String resetCodeResendWaitLabel = 'أرسل الرمز مرة أخرى (بعد دقيقة)';

/// Shown after a new code was sent.
const String resetCodeResentMessage =
    'أرسلنا رمزًا جديدًا. استخدم آخر رمز وصلك.';

/// The button that goes back to the e-mail field.
const String resetCodeChangeEmailLabel = 'تغيير البريد';
