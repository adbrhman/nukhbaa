/// The single place that turns a typed [AppError] into a user-facing message.
///
/// Every failure in the app arrives as `shared`'s `AppError` (from a
/// `Result.err` produced by `api_client`). Presentation logic lives here once
/// so screens never branch on raw `code` strings ad hoc — they call
/// [ErrorPresenter.message] (and, where useful, [ErrorPresenter.isRetryable]).
///
/// Messages are intentionally terse and non-technical; the stable `code` is
/// used to special-case the handful of business outcomes the Core screens must
/// distinguish (e.g. "you haven't predicted yet" vs a real error), keeping the
/// mapping in one auditable table rather than scattered across widgets.
library;

import 'package:shared/shared.dart';

/// Maps typed errors to human text. Pure and stateless.
abstract final class ErrorPresenter {
  /// A short, user-readable description of [error].
  ///
  /// Known stable codes are given tailored copy; everything else falls back to
  /// a message keyed on the [ErrorKind] so the user always sees something
  /// sensible and never a raw exception.
  static String message(AppError error) {
    switch (error.code) {
      case 'auth.invalid_credentials':
        return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      case 'auth.account_suspended':
        return 'تم إيقاف هذا الحساب. تواصل مع الإدارة.';
      case 'leaderboard.not_a_participant':
        return 'لست مشاركًا في هذا الموسم، لذلك لا يظهر لك ترتيبه.';
      case 'prediction.fixture_locked':
        return 'انطلقت المباراة، ولم يعد التوقع متاحًا.';
      case 'prediction.daily_double_exceeded':
        return 'يمكنك مضاعفة النقاط في مباراة واحدة فقط كل يوم.';
      case 'prediction.fixture_not_scheduled':
        return 'لم يُحدَّد موعد هذه المباراة بعد، لذلك لا يمكن توقعها.';
      case 'prediction.fixture_not_in_season':
        return 'هذه المباراة ليست ضمن الموسم الحالي.';
      case 'prediction.not_found':
        return 'لم ترسل توقعًا لهذه المباراة بعد.';
      case 'prediction.round_not_locked':
        return 'تظهر توقعات اللاعبين الآخرين بعد انطلاق المباراة.';
      case 'prediction.not_a_participant':
        return 'لم تنضم إلى هذه المسابقة بعد.';
      case 'competition.not_found':
        return 'تعذّر العثور على هذه المسابقة.';
      case 'competition.round_not_found':
        return 'تعذّر العثور على هذه الجولة.';
      case 'prediction.round_out_of_sequence':
        return 'لا يمكن توقع هذه الجولة قبل إكمال الجولات السابقة.';
      case 'scoring.fixture_not_started':
        return 'لا يمكن تسجيل نتيجة مباراة قبل موعد انطلاقها.';
      case 'api_client.timeout':
        return 'تأخر الخادم في الرد. حاول مرة أخرى.';
    }

    return switch (error.kind) {
      ErrorKind.authorization =>
        'انتهت جلستك أو لم تسجّل الدخول. سجّل الدخول مرة أخرى.',
      ErrorKind.invariant => _arabicOr(
        error,
        'لا يمكن تنفيذ هذا الإجراء الآن.',
      ),
      ErrorKind.validation => _arabicOr(
        error,
        'بعض البيانات المدخلة غير صحيحة.',
      ),
      ErrorKind.transient =>
        'تعذّر الاتصال بالخادم. تحقّق من اتصالك وحاول مرة أخرى.',
    };
  }

  /// Arabic script, to tell a server message written for users apart from a
  /// developer-facing English one.
  static final RegExp _arabicScript = RegExp('[\u0600-\u06FF]');

  /// The server's own message when it is already Arabic; otherwise
  /// [fallback] with the stable code, so the user never reads English and an
  /// admin can still tell which rule refused the action.
  static String _arabicOr(AppError error, String fallback) {
    if (_arabicScript.hasMatch(error.message)) return error.message;
    return '$fallback (${error.code})';
  }

  /// Whether the user should be offered a "retry" affordance for [error].
  ///
  /// Only transient/infrastructure failures are safely retryable
  /// ([AppError.isRetryable]); a terminal business/validation/authorization
  /// outcome is not retried by re-issuing the same request.
  static bool isRetryable(AppError error) => error.isRetryable;

  /// Whether [error] means the caller's session is missing or invalid, so the
  /// app should route them back to sign-in.
  static bool isAuthFailure(AppError error) =>
      error.kind == ErrorKind.authorization;
}
