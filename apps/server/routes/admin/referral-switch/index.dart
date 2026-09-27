import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `PUT /admin/referral-switch` -- turns the invitation system on or off
/// (migration 0075). Body: `{"enabled": true | false}`; answers the stored
/// value. Admin only. A missing or non-boolean `enabled` is `400`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminSetReferralsEnabled(
    principal: principal,
    enabled: ReferralSwitchDto.enabledOf(
      (bodyResult as Ok<Map<String, Object?>>).value,
    ),
  );

  return switch (result) {
    Ok<bool>(:final value) => Response.json(
      body: ReferralSwitchDto(enabled: value).toJson(),
    ),
    Err<bool>(:final error) => errorResponse(error),
  };
}
