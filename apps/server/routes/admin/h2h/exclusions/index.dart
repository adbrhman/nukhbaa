import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_league_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/h2h/exclusions` -- keeps a Riyadh day from automatic
/// approval, or lifts that (migration 0101). Body: `{"day": "YYYY-MM-DD",
/// "excluded": true|false}`. Answers `{"changed": bool}`; only a change is
/// written to the admin log. An admin may still approve an excluded day by
/// hand, which lifts the exclusion.
///
/// A day that is not a `YYYY-MM-DD` date is `400` (`h2h.day_invalid`), a
/// missing `excluded` is `400` (`h2h.excluded_invalid`), and a day before
/// today is `400` (`h2h.day_past`).
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;
  final raw = body['day'];
  final day = raw is String ? parseIsoDay(raw) : null;
  if (day == null) {
    return errorResponse(
      const AppError.validation(
        'h2h.day_invalid',
        'Field "day" must be a date written YYYY-MM-DD',
      ),
    );
  }
  final excluded = body['excluded'];
  if (excluded is! bool) {
    return errorResponse(
      const AppError.validation(
        'h2h.excluded_invalid',
        'Field "excluded" must be true or false',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.h2hAdminDesk.controls.setDayExcluded(
    principal: principal,
    day: day,
    excluded: excluded,
  );

  return switch (result) {
    Ok<bool>(:final value) => Response.json(body: {'changed': value}),
    Err<bool>(:final error) => errorResponse(error),
  };
}
