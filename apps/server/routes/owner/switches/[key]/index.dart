import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/owner_switch_wire.dart';
import 'package:shared/shared.dart';

// NK289_06
/// `PUT /owner/switches/{key}` `{"is_on": bool, "reason": "..."}` -- an
/// owner seat turns one of the owners' switches on or off, always for a
/// reason (`OwnerSwitchBoard`, script 289, migration 0218). Answers the
/// switch as it now stands. The change is kept on the switch's row (who,
/// when, why) and in the owners' own audit log (script 287).
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287). A
/// flag that is not a bool is `400 owner.switch_invalid`; an unknown key
/// `400 owner.switch_unknown`; a blank or long reason
/// `400 owner.reason_required`. `405` on any other method.
Future<Response> onRequest(RequestContext context, String key) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final board = root.ownerSwitchBoard;
  if (board == null) {
    return errorResponse(
      const AppError.transient(
        'owner.switches_unavailable',
        'The owner switches are unavailable',
      ),
    );
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final Map<String, Object?> body =
      (bodyResult as Ok<Map<String, Object?>>).value;
  final Object? on = body['is_on'];
  if (on is! bool) {
    return errorResponse(
      const AppError.validation(
        'owner.switch_invalid',
        'is_on must be true or false',
      ),
    );
  }
  final Object? reason = body['reason'];
  final principal = context.read<AuthenticatedUser>();
  final Result<OwnerSwitchState> set = await board.set(
    principal: principal,
    key: key,
    on: on,
    reason: reason is String ? reason : null,
  );
  return switch (set) {
    Ok<OwnerSwitchState>(:final value) => Response.json(
      body: ownerSwitchWire(value, principal.userId).toJson(),
    ),
    Err<OwnerSwitchState>(:final error) => errorResponse(error),
  };
}
