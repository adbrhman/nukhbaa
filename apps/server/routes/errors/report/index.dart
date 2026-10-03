import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/rate_limit.dart';
import 'package:shared/shared.dart';

/// `POST /errors/report` -- one unexpected error the app caught (migration
/// 0087), kept in the admin dashboard's error log.
///
/// Open before sign-in: an error on the sign-in or sign-up screen matters
/// as much as any other. A valid bearer token names the player; a missing
/// or expired one is no reason to drop the report. Every key outside
/// [ClientErrorReportDto.fields] is refused, the body is capped like every
/// JSON body (64 KiB), and each device and address may send only so many
/// (`limitErrorReport`). Secrets are removed by `RecordError` before
/// anything is kept; the install id is used for the limit only.
///
/// Answers `200` with the problem code the error was kept under.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;
  final invalid = _invalid(body);
  if (invalid != null) {
    return errorResponse(invalid);
  }
  final dto = ClientErrorReportDto.fromJson(body);

  final root = await context.read<Future<CompositionRoot>>();
  final header = context.request.headers[HttpHeaders.authorizationHeader];
  AuthenticatedUser? principal;
  if (header != null && header.trim().isNotEmpty) {
    final verified = await root.authenticateRequest(header);
    if (verified case Ok<AuthenticatedUser>(:final value)) {
      principal = value;
    }
  }

  final limited = limitErrorReport(
    device: dto.installId ?? principal?.userId.value,
    address: clientAddress(context.request.headers),
  );
  if (limited != null) {
    return limited;
  }

  final record = root.recordError;
  if (record == null) {
    return errorResponse(
      const AppError.transient(
        'errors.unavailable',
        'The error log is unavailable',
      ),
    );
  }
  final report = ErrorReport(
    source: dto.source,
    errorType: dto.errorType,
    errorCode: dto.errorCode,
    message: dto.message,
    stack: dto.stack,
    route: dto.route,
    severity: dto.fatal ? ErrorSeverity.high : ErrorSeverity.medium,
    build: dto.build,
    userId: principal?.userId.value,
    requestId: dto.requestId,
    device: dto.device,
    os: dto.os,
    browser: dto.browser,
  );
  final result = await record(report);
  return switch (result) {
    Ok<RecordedError>() => Response.json(
      body: ClientErrorReportAckDto(
        problemCode: RecordError.identify(report).problemCode,
      ).toJson(),
    ),
    Err<RecordedError>(:final error) => errorResponse(error),
  };
}

/// The app's own sources; `server` is never accepted from a client.
const Set<String> _clientSources = <String>{'android', 'ios', 'web'};

const Set<String> _optionalStrings = <String>{
  'error_code',
  'stack',
  'route',
  'device',
  'os',
  'browser',
  'request_id',
  'install_id',
};

AppError? _invalid(Map<String, Object?> body) {
  for (final key in body.keys) {
    if (!ClientErrorReportDto.fields.contains(key)) {
      return AppError.validation(
        'errors.unknown_field',
        'Field "$key" is not accepted',
      );
    }
  }
  final source = body['source'];
  if (source is! String || !_clientSources.contains(source)) {
    return const AppError.validation(
      'errors.invalid_source',
      'Field "source" must be android, ios or web',
    );
  }
  for (final field in const ['error_type', 'message', 'build']) {
    if (body[field] is! String) {
      return AppError.validation(
        'request.field_missing',
        'Field "$field" is required and must be a string',
      );
    }
  }
  for (final field in _optionalStrings) {
    final value = body[field];
    if (value != null && value is! String) {
      return AppError.validation(
        'request.field_invalid',
        'Field "$field" must be a string',
      );
    }
  }
  final fatal = body['fatal'];
  if (fatal != null && fatal is! bool) {
    return const AppError.validation(
      'request.field_invalid',
      'Field "fatal" must be a boolean',
    );
  }
  final version = body['schema_version'];
  if (version != null && version is! int) {
    return const AppError.validation(
      'request.field_invalid',
      'Field "schema_version" must be an integer',
    );
  }
  return null;
}
