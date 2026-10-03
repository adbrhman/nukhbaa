import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/error_log_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /admin/errors` -- the admin error log (migration 0087): the counts
/// of every list, one list, and the admins an error can be assigned to.
///
/// Query: `list` (`all`, `new`, `recurring`, `critical`; default `all`),
/// `source`, `build`, and `code` -- a problem code a player sent, which
/// finds its error in every list. Admins only (`AdminErrorLog`); behind
/// `bearerAuth` like all of `/admin`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final log = root.adminErrorLog;
  if (log == null) {
    return errorResponse(
      const AppError.transient(
        'errors.unavailable',
        'The error log is unavailable',
      ),
    );
  }

  final query = context.request.uri.queryParameters;
  final kind = ErrorListKind.fromWire(query['list'] ?? 'all');
  if (kind == null) {
    return errorResponse(
      const AppError.validation('errors.invalid_list', 'قائمة غير معروفة'),
    );
  }

  final result = await log.list(
    principal: principal,
    kind: kind,
    source: query['source'],
    build: query['build'],
    problemCode: query['code'],
  );
  return switch (result) {
    Ok<AdminErrorList>(:final value) => Response.json(
      body: errorListToDto(value).toJson(),
    ),
    Err<AdminErrorList>(:final error) => errorResponse(error),
  };
}
