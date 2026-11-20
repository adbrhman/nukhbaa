import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

// NK294_06
/// `POST /owner/admins/{id}` `{"action": "promote" | "revoke" |
/// "end_sessions", "reason": "..."}` -- an owner seat makes the player
/// {id} an admin, takes the role back (his sessions end with it), or ends
/// the account's sessions (`OwnerAdmins`, script 294, migration 0223).
/// Answers `{"action": ..., "sessions_ended": n}`.
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287). An
/// owner seat is never revoked: `409 owner.cannot_revoke_owner`. A blank or
/// long reason is `400 owner.reason_required`; another action
/// `400 owner.action_invalid`. `405` on any other method.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final OwnerAdmins? admins = root.ownerAdmins;
  if (admins == null) {
    return errorResponse(
      const AppError.transient(
        'owner.admins_unavailable',
        'The admins are unavailable',
      ),
    );
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final Map<String, Object?> body =
      (bodyResult as Ok<Map<String, Object?>>).value;
  final Object? action = body['action'];
  final Object? reason = body['reason'];
  final String act = action is String ? action : '';
  final Result<int> done = await admins.act(
    principal: context.read<AuthenticatedUser>(),
    userId: id,
    action: act,
    reason: reason is String ? reason : null,
  );
  return switch (done) {
    Ok<int>(:final value) => Response.json(
      body: {'action': act, 'sessions_ended': value},
    ),
    Err<int>(:final error) => errorResponse(error),
  };
}
