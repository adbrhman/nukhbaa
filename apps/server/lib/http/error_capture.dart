import 'dart:convert';
import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/http/request_scope.dart';
import 'package:shared/shared.dart';

/// Finds the use-case that keeps errors; null when there is none (tests,
/// or a composition root that could not be built).
typedef ErrorRecorderLookup = Future<RecordError?> Function();

/// How long one recording may take before the response goes out without
/// it. A failed request is already slow; it must not wait on the log.
const Duration errorRecordTimeout = Duration(seconds: 2);

/// The most recordings running at once. When the database is the failure,
/// every request fails together; past this many the rest are skipped
/// rather than queued on a pool that is already exhausted.
const int maxConcurrentErrorRecords = 4;

int _recordsInFlight = 0;

final RegExp _buildShape = RegExp(r'^[0-9A-Za-z._-]{1,40}$');

/// The build this server runs, as the error log records it: the first 7
/// characters of Northflank's `NF_DEPLOYMENT_SHA` (the deployed commit),
/// else of `NUKHBA_BUILD_SHA`, else `server-dev` for a local run.
String serverBuild(Map<String, String> environment) {
  for (final key in const ['NF_DEPLOYMENT_SHA', 'NUKHBA_BUILD_SHA']) {
    final value = environment[key]?.trim() ?? '';
    final short = value.length > 7 ? value.substring(0, 7) : value;
    if (_buildShape.hasMatch(short)) {
      return short;
    }
  }
  return 'server-dev';
}

/// Wraps [handler] so that every request gets a [RequestScope] with a new
/// id, returned in [requestIdHeader] on every response, and every response
/// of 500 or above -- an `AppError` a route answered with, a bare 5xx, or
/// an exception that escaped the handler (answered here with the uniform
/// `server.unexpected` envelope) -- is kept in the error log (migration
/// 0087) with the request id, the route, the player and the build.
///
/// A 5xx error envelope also carries the `problem_code` the error was kept
/// under, for the app to show the player; recording itself never changes
/// the response: a failure to record is printed and the response goes out
/// as it was.
Handler captureServerErrors(
  Handler handler, {
  required ErrorRecorderLookup recorder,
  String? build,
}) {
  final thisBuild = build ?? serverBuild(Platform.environment);
  return (context) async {
    final scope = RequestScope(RequestScope.newRequestId());
    Response response;
    Object? thrown;
    StackTrace? thrownStack;
    try {
      response = await scope.run(() => handler(context));
    } on Object catch (error, stackTrace) {
      // Anything that escapes a handler used to be answered by the framework
      // with a bare 500 carrying none of the CORS headers -- so the web
      // build saw an opaque failure rather than the error. Same envelope as
      // every other error response.
      // ignore: avoid_print
      print(
        '[middleware] unhandled failure (${scope.requestId}): '
        '$error\n$stackTrace',
      );
      thrown = error;
      thrownStack = stackTrace;
      response = Response.json(
        statusCode: HttpStatus.internalServerError,
        body: const ErrorResponseDto(
          code: 'server.unexpected',
          message: 'Unexpected server error',
        ).toJson(),
      );
    }
    if (response.statusCode >= HttpStatus.internalServerError) {
      final report = _reportFor(
        context.request,
        response.statusCode,
        scope,
        thisBuild,
        thrown,
        thrownStack,
      );
      await keepErrorReport(recorder, report);
      response = await _withProblemCode(
        response,
        RecordError.identify(report).problemCode,
      );
    }
    return response.copyWith(
      headers: {...response.headers, requestIdHeader: scope.requestId},
    );
  };
}

/// Keeps [report] through the use-case [recorder] finds. Never throws and
/// never takes longer than twice [errorRecordTimeout]; a failure is
/// printed, which is all the container log can do.
Future<void> keepErrorReport(
  ErrorRecorderLookup recorder,
  ErrorReport report,
) async {
  if (_recordsInFlight >= maxConcurrentErrorRecords) {
    // ignore: avoid_print
    print('[error-log] skipped: recordings already in flight');
    return;
  }
  _recordsInFlight++;
  try {
    final record = await recorder().timeout(errorRecordTimeout);
    if (record == null) {
      return;
    }
    final result = await record(report).timeout(errorRecordTimeout);
    if (result case Err<RecordedError>(:final error)) {
      // ignore: avoid_print
      print('[error-log] not recorded: ${error.code} ${error.message}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('[error-log] not recorded: $error');
  } finally {
    _recordsInFlight--;
  }
}

// The same envelope with `problem_code` added. A body that is not an
// error envelope (a bare 5xx) goes out unchanged.
Future<Response> _withProblemCode(Response response, String code) async {
  final String body;
  try {
    body = await response.body();
  } on Object {
    return response;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (decoded is Map<String, Object?> && decoded['code'] is String) {
    return Response.json(
      statusCode: response.statusCode,
      body: <String, Object?>{...decoded, 'problem_code': code},
    );
  }
  return Response(
    statusCode: response.statusCode,
    body: body,
    headers: {
      for (final entry in response.headers.entries)
        if (entry.key.toLowerCase() != 'content-length') entry.key: entry.value,
    },
  );
}

ErrorReport _reportFor(
  Request request,
  int status,
  RequestScope scope,
  String build,
  Object? thrown,
  StackTrace? thrownStack,
) {
  final route =
      '${request.method.name.toUpperCase()} '
      '${ErrorFingerprint.normalizeVariable(request.uri.path)}';
  final query = request.uri.queryParameters;
  final input = <String, Object?>{
    'method': request.method.name.toUpperCase(),
    'path': request.uri.path,
    'status': status,
    if (query.isNotEmpty) 'query': query,
  };
  final appError = scope.serverError;
  if (thrown != null) {
    return ErrorReport(
      source: 'server',
      errorType: thrown.runtimeType.toString(),
      errorCode: 'server.unexpected',
      message: thrown.toString(),
      stack: thrownStack?.toString(),
      route: route,
      severity: ErrorSeverity.high,
      build: build,
      userId: scope.userId,
      requestId: scope.requestId,
      browser: request.headers['user-agent'],
      requestInput: input,
    );
  }
  if (appError != null) {
    final cause = appError.cause;
    return ErrorReport(
      source: 'server',
      errorType: 'AppError',
      errorCode: appError.code,
      message: cause == null ? appError.message : '${appError.message}: $cause',
      stack: _withoutEnvelopeFrames(scope.serverErrorStack),
      route: route,
      severity: ErrorSeverity.medium,
      build: build,
      userId: scope.userId,
      requestId: scope.requestId,
      browser: request.headers['user-agent'],
      requestInput: input,
    );
  }
  return ErrorReport(
    source: 'server',
    errorType: 'HttpStatus',
    message: 'HTTP $status',
    route: route,
    severity: ErrorSeverity.medium,
    build: build,
    userId: scope.userId,
    requestId: scope.requestId,
    browser: request.headers['user-agent'],
    requestInput: input,
  );
}

// errorResponse() notes the stack where it was called; its own frame is the
// same for every route, so the route's frame must come first.
String? _withoutEnvelopeFrames(StackTrace? stack) {
  if (stack == null) {
    return null;
  }
  return stack
      .toString()
      .split('\n')
      .where((line) => !line.contains('http/error_envelope.dart'))
      .join('\n');
}
