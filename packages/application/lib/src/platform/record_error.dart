/// Use-case: keep one occurrence of an error in the error log (migration
/// 0087).
library;

import 'dart:convert';

import 'package:application/src/common/clock.dart';
import 'package:application/src/platform/alert_admins_of_error.dart';
import 'package:application/src/platform/error_redaction.dart';
import 'package:application/src/platform/ports/error_log_repository.dart';
import 'package:shared/shared.dart';

/// An error as it was caught, before anything is removed from it.
final class ErrorReport {
  /// Creates a report.
  const ErrorReport({
    required this.source,
    required this.errorType,
    required this.message,
    required this.severity,
    required this.build,
    this.errorCode,
    this.stack,
    this.route,
    this.userId,
    this.requestId,
    this.device,
    this.os,
    this.browser,
    this.requestInput,
  });

  /// `server`, `android`, `ios` or `web`.
  final String source;

  /// The error's runtime type.
  final String errorType;

  /// What went wrong, as caught.
  final String message;

  /// How bad it is.
  final ErrorSeverity severity;

  /// The build that hit it.
  final String build;

  /// The stable `AppError` code, when there is one.
  final String? errorCode;

  /// The whole stack, as caught.
  final String? stack;

  /// `GET /seasons/:id`, a screen, or `job rescore`.
  final String? route;

  /// The signed-in player, when there was one.
  final String? userId;

  /// The server request it happened in.
  final String? requestId;

  /// The device model.
  final String? device;

  /// The operating system.
  final String? os;

  /// The browser or HTTP client.
  final String? browser;

  /// The request's inputs, as decoded JSON.
  final Map<String, Object?>? requestInput;
}

/// Keeps one occurrence of an error: redacts every field (the one place
/// secrets are removed, [ErrorRedaction]), fingerprints it
/// ([ErrorFingerprint]), caps every field to what the table accepts, and
/// hands it to `ops.record_error()`.
///
/// Never throws; returns a typed [Result].
final class RecordError {
  /// Creates the use-case over its collaborators.
  const RecordError({
    required ErrorLogRepository errors,
    required Clock clock,
    AlertAdminsOfError? alerts,
  }) : _errors = errors,
       _clock = clock,
       _alerts = alerts;

  final ErrorLogRepository _errors;
  final Clock _clock;

  /// Tells the admins about an occurrence worth it (migration 0089); null
  /// in tests that do not provide one. Its failure never fails the record.
  final AlertAdminsOfError? _alerts;

  /// Where an error can come from.
  static const Set<String> sources = <String>{
    'server',
    'android',
    'ios',
    'web',
  };

  /// The build recorded when the reported one is malformed.
  static const String unknownBuild = 'unknown';

  /// The largest request input kept, in bytes of JSON.
  static const int maxInputBytes = 8192;

  static final RegExp _build = RegExp(r'^[0-9A-Za-z._-]{1,40}$');
  static final RegExp _requestId = RegExp(r'^[0-9A-Za-z-]{8,64}$');
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  /// Keeps one occurrence of [report].
  Future<Result<RecordedError>> call(ErrorReport report) async {
    if (!sources.contains(report.source)) {
      return const Result.err(
        AppError.validation('errors.invalid_source', 'Invalid error source'),
      );
    }
    final stack = _stackOf(report);
    final route = _capOrNull(_redactOrNull(report.route), 300);
    final errorType = _typeOf(report);
    final errorCode = _codeOf(report);
    final message = _cap(
      _nonBlank(ErrorRedaction.text(report.message), errorType),
      1000,
    );
    final identity = identify(report);
    final top = ErrorFingerprint.topFrames(stack);
    final where = top.isEmpty ? null : top.first;
    return _recordAndAlert(
      ErrorOccurrence(
        fingerprint: identity.fingerprint,
        problemCode: identity.problemCode,
        source: report.source,
        errorType: errorType,
        errorCode: errorCode,
        message: message,
        locationFile: where == null ? null : _cap(where.file, 300),
        locationLine: where?.line,
        locationSymbol: where == null ? null : _cap(where.symbol, 300),
        severity: report.severity,
        build: _build.hasMatch(report.build) ? report.build : unknownBuild,
        occurredAt: _clock.nowUtc(),
        userId: report.userId != null && _uuid.hasMatch(report.userId!)
            ? report.userId
            : null,
        requestId:
            report.requestId != null && _requestId.hasMatch(report.requestId!)
            ? report.requestId
            : null,
        route: route,
        device: _capOrNull(_redactOrNull(report.device), 120),
        os: _capOrNull(_redactOrNull(report.os), 120),
        browser: _capOrNull(_redactOrNull(report.browser), 200),
        stack: stack,
        requestInputJson: _input(report.requestInput),
      ),
    );
  }

  Future<Result<RecordedError>> _recordAndAlert(
    ErrorOccurrence occurrence,
  ) async {
    final recorded = await _errors.record(occurrence);
    final alerts = _alerts;
    if (alerts != null && recorded is Ok<RecordedError>) {
      try {
        await alerts(recorded: recorded.value, occurrence: occurrence);
      } on Object {
        // The alert is best effort; the occurrence is already kept.
      }
    }
    return recorded;
  }

  /// The identity [report] is kept under, computed from its fields as they
  /// are stored. The server shows its [ErrorFingerprint.problemCode] in a
  /// 5xx answer; the app computes the same from what it sends.
  ///
  /// The route identifies a server error that has no stack (`GET
  /// /seasons/:id`, `job rescore`). An app error never uses its route: the
  /// app shows the code before it knows where the report will be filed, so
  /// it computes it from the type, the code and the stack alone.
  static ErrorFingerprint identify(ErrorReport report) => ErrorFingerprint.of(
    source: report.source,
    errorType: _typeOf(report),
    errorCode: _codeOf(report),
    stack: _stackOf(report),
    route: report.source == 'server'
        ? _capOrNull(_redactOrNull(report.route), 300)
        : null,
  );

  static String _typeOf(ErrorReport report) =>
      _cap(_nonBlank(report.errorType, 'Error'), 120);

  static String? _codeOf(ErrorReport report) =>
      _capOrNull(_redactOrNull(report.errorCode), 120);

  static String? _stackOf(ErrorReport report) =>
      _capOrNull(_redactOrNull(report.stack), 16000);

  static String? _input(Map<String, Object?>? input) {
    if (input == null) {
      return null;
    }
    final encoded = jsonEncode(ErrorRedaction.json(input));
    if (utf8.encode(encoded).length > maxInputBytes) {
      return jsonEncode(<String, Object?>{'truncated': true});
    }
    return encoded;
  }

  static String? _redactOrNull(String? value) =>
      value == null || value.trim().isEmpty ? null : ErrorRedaction.text(value);

  static String _nonBlank(String value, String fallback) =>
      value.trim().isEmpty ? fallback : value.trim();

  static String _cap(String value, int max) =>
      value.length > max ? value.substring(0, max) : value;

  static String? _capOrNull(String? value, int max) =>
      value == null ? null : _cap(value, max);
}
