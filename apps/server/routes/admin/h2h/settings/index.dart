import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_admin_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `PUT /admin/h2h/settings` -- replaces the head-to-head league's settings
/// (migration 0101). Body: `{"auto_approve": bool, "lead_hours": 1..24,
/// "min_active_days": 1..28}`. Answers the settings as stored; the change is
/// written to the admin log.
///
/// A missing or mistyped field is `400` (`h2h.settings_invalid`); a value
/// out of its range is `400` (`h2h.settings_out_of_range`).
///
/// Admin only: the gate lives in the use-case; a non-admin is `401`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;
  final autoApprove = body['auto_approve'];
  final leadHours = body['lead_hours'];
  final minActiveDays = body['min_active_days'];
  if (autoApprove is! bool || leadHours is! int || minActiveDays is! int) {
    return errorResponse(
      const AppError.validation(
        'h2h.settings_invalid',
        'Send "auto_approve" (true/false), "lead_hours" and '
            '"min_active_days" (whole numbers)',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.h2hAdminDesk.controls.saveSettings(
    principal: principal,
    autoApprove: autoApprove,
    leadHours: leadHours,
    minActiveDays: minActiveDays,
  );

  return switch (result) {
    Ok<H2hSettings>(:final value) => Response.json(
      body: h2hSettingsToDto(value).toJson(),
    ),
    Err<H2hSettings>(:final error) => errorResponse(error),
  };
}
