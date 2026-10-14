import 'dart:io';

import 'package:application/application.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_capture.dart';
import 'package:shared/shared.dart';

/// Keeps a failed scheduled job in the error log (migration 0087): a run
/// that answered an `AppError` or threw. The route reads `job <name>`, so
/// the same failure on every tick is one error with a counter.
///
/// [critical] marks the jobs whose failure leaves points, results or the
/// monthly contest wrong until someone acts.
///
/// Never throws (see [keepErrorReport]); the caller's printed line stays
/// the container log's copy.
Future<void> reportJobFailure(
  CompositionRoot root, {
  required String job,
  required Object error,
  StackTrace? stackTrace,
  bool critical = false,
}) {
  final String errorType;
  final String? errorCode;
  final String message;
  if (error is AppError) {
    errorType = 'AppError';
    errorCode = error.code;
    message = error.cause == null
        ? error.message
        : '${error.message}: ${error.cause}';
  } else {
    errorType = error.runtimeType.toString();
    errorCode = null;
    message = error.toString();
  }
  return keepErrorReport(
    () async => root.recordError,
    ErrorReport(
      source: 'server',
      errorType: errorType,
      errorCode: errorCode,
      message: message,
      stack: stackTrace?.toString(),
      route: 'job $job',
      severity: critical ? ErrorSeverity.critical : ErrorSeverity.high,
      build: serverBuild(Platform.environment),
    ),
  );
}

/// Keeps a matter a scheduled job left for an admin in the error log (audit
/// C-03): a match whose provider data the sync could not apply by itself.
///
/// It is filed as critical under the job and its [subject] (the match), so
/// each matter is an entry of its own: the admins are pushed the first time
/// it is seen (`AlertAdminsOfError`), and the home page's «يحتاج تدخلك»
/// counts it until it is handled. The same matter seen on a later run only
/// adds to its counter. [code] says what kind of matter it is; [message]
/// says, in Arabic, what happened and what to do.
///
/// Never throws (see [keepErrorReport]).
Future<void> reportNeedsAdmin(
  CompositionRoot root, {
  required String job,
  required String subject,
  required String code,
  required String message,
}) => keepErrorReport(
  () async => root.recordError,
  ErrorReport(
    source: 'server',
    errorType: 'NeedsAdmin',
    errorCode: code,
    message: message,
    route: 'job $job: $subject',
    severity: ErrorSeverity.critical,
    build: serverBuild(Platform.environment),
  ),
);
