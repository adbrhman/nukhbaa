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
