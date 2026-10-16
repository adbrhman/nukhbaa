import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/fixture_merge_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/fixtures/{id}/merge` -- merges fixture `{id}`, a copy of a
/// match, into the copy kept (command `AdminMergeFixtureCopies`, migration
/// 0176, script 95), or previews it.
///
/// Body: `{"into": uuid, "apply": bool}`. Answers what the merge did, or
/// would do with `apply` false, as a `FixtureMergeReportDto` (`200`). A
/// merge the database refuses (`fixture_merge_*`: not one match, the kept
/// copy hidden, already merged, ...) is `409` with an Arabic message. A
/// missing or wrong-typed field is `400`; any other method is `405`. Admin
/// only: the gate lives in the use-case.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final intoResult = optionalString(body, 'into');
  if (intoResult is Err<String?>) {
    return errorResponse(intoResult.error);
  }
  final Object? apply = body['apply'];
  if (apply is! bool) {
    return errorResponse(
      const AppError.validation(
        'request.field_missing',
        'Field "apply" is required and must be true or false',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminMergeFixtureCopies(
    principal: principal,
    duplicateId: id,
    keptId: (intoResult as Ok<String?>).value,
    apply: apply,
  );

  return switch (result) {
    Ok<FixtureMergeReport>(:final value) => Response.json(
      body: fixtureMergeReportToDto(value).toJson(),
    ),
    Err<FixtureMergeReport>(:final error) => errorResponse(error),
  };
}
