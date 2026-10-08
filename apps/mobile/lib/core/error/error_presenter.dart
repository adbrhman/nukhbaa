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

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

/// Maps typed errors to human text. Pure and stateless.
abstract final class ErrorPresenter {
  /// A short, user-readable description of [error].
  ///
  /// Known stable codes are given tailored copy; everything else falls back to
  /// a message keyed on the [ErrorKind] so the user always sees something
  /// sensible and never a raw exception.
  ///
  /// An unexpected failure also carries its problem code on a second line
  /// ([problemCodeLabel], see [problemCode]), never a stack or a cause.
  static String message(AppError error) {
    final String text = _message(error);
    final String? code = problemCode(error);
    return code == null ? text : '$text\n$problemCodeLabel $code';
  }

  /// The words before a problem code in [message].
  static const String problemCodeLabel = 'رمز المشكلة:';

  /// Finds the problem code [message] put in [text], for a copy button.
  static String? problemCodeIn(String text) =>
      _problemCodeInText.firstMatch(text)?.group(1);

  static final RegExp _problemCodeInText = RegExp(
    '$problemCodeLabel ([A-HJ-NP-Z2-9]{4})',
  );

  /// Where this build runs, as the error log names it.
  static String get errorSource => kIsWeb
      ? 'web'
      : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

  /// Whether a failed API call is the app's to report (migration 0087): the
  /// server answered nothing usable -- a 5xx without its own problem code,
  /// a timeout, a body that could not be read. An expected refusal (wrong
  /// password, a name taken, a match that kicked off) is a correct answer,
  /// and being offline is no fault of the service: neither is reported.
  static bool isReportable(AppError error) {
    if (error.problemCode != null) return false;
    return error.code == apiErrorTimeout ||
        error.code == apiErrorMalformedResponse ||
        (error.code == apiErrorUnexpectedStatus &&
            error.kind == ErrorKind.transient);
  }

  /// The code the player reads out for [error]: the server's when it
  /// logged the failure, the app's own (the same the server will compute
  /// from the app's report) when [isReportable], else null.
  static String? problemCode(AppError error) {
    final String? fromServer = error.problemCode;
    if (fromServer != null && fromServer.isNotEmpty) return fromServer;
    if (!isReportable(error)) return null;
    return ErrorFingerprint.of(
      source: errorSource,
      errorType: 'AppError',
      errorCode: error.code,
    ).problemCode;
  }

  static String _message(AppError error) {
    switch (error.code) {
      case 'auth.invalid_credentials':
        return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      case 'auth.account_suspended':
        return 'تم إيقاف هذا الحساب. تواصل مع الإدارة.';
      case 'leaderboard.not_a_participant':
        return 'لست مشاركًا في هذا الموسم، لذلك لا يظهر لك ترتيبه.';
      case 'prediction.fixture_locked':
        return 'انطلقت المباراة، ولم يعد التوقع متاحًا.';
      case 'prediction.fixture_unavailable':
        return 'هذه المباراة غير متاحة الآن.';
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
      case 'prediction.fixture_not_started':
        return 'تظهر توقعات اللاعبين الآخرين بعد انطلاق المباراة.';
      case 'prediction.not_a_participant':
        return 'لم تنضم إلى هذه المسابقة بعد.';
      case 'competition.not_found':
        return 'تعذّر العثور على هذه المسابقة.';
      case 'competition.round_not_found':
        return 'تعذّر العثور على هذه الجولة.';
      case 'prediction.round_out_of_sequence':
        return 'لا يمكن توقع هذه الجولة قبل إكمال الجولات السابقة.';
      case 'competition.fixture_has_predictions':
        return 'توقّعها لاعبون، فلا يمكن حذفها. أخفِها بدلاً من ذلك.';
      case 'competition.fixture_result_already_recorded':
        return 'سُجّلت نتيجتها، فلا يمكن حذفها. أخفِها بدلاً من ذلك.';
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
