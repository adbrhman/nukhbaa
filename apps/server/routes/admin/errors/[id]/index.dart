import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/error_log_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `GET /admin/errors/{id}` -- one error of the error log with its last
/// samples and its builds (migration 0087).
///
/// `POST /admin/errors/{id}` -- an admin changes its status, severity,
/// assignee or notes ([AdminErrorUpdateDto]; only the keys sent change).
/// The change is recorded in `admin.audit_log` (migration 0088). Answers
/// the error as it now stands.
///
/// An unknown error is `409` `errors.not_found`; an id that is not a number
/// `400`. Admins only; behind `bearerAuth` like all of `/admin`.
Future<Response> onRequest(RequestContext context, String id) async {
  final method = context.request.method;
  if (method != HttpMethod.get && method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final groupId = int.tryParse(id);
  if (groupId == null || groupId < 1) {
    return errorResponse(
      const AppError.validation('errors.invalid_id', 'رقم الخطأ غير صالح'),
    );
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

  final Result<ErrorGroupDetail> result;
  if (method == HttpMethod.get) {
    result = await log.detail(principal: principal, id: groupId);
  } else {
    final bodyResult = await readJsonObject(context.request);
    if (bodyResult is Err<Map<String, Object?>>) {
      return errorResponse(bodyResult.error);
    }
    final change = AdminErrorUpdateDto.fromJson(
      (bodyResult as Ok<Map<String, Object?>>).value,
    );
    result = await log.update(
      principal: principal,
      id: groupId,
      status: change.status,
      severity: change.severity,
      assigneeId: change.assigneeId,
      notes: change.notes,
    );
  }
  return switch (result) {
    Ok<ErrorGroupDetail>(:final value) => Response.json(
      body: errorDetailToDto(value).toJson(),
    ),
    Err<ErrorGroupDetail>(:final error) => errorResponse(error),
  };
}
