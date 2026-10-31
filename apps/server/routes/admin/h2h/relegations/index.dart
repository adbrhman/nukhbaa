import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/h2h/relegations` -- an admin relegates an elite player by
/// hand (cheating, a breach; NK183, migration 0189). Body:
/// `{"user_id": "<uuid>", "reason": "<1..300 characters>"}`. The player
/// swaps seats, from the next round not started, with the substitute the
/// rules take; he does not come back this month. Both are told by push,
/// and the swap is written to the admin log. Answers `201`
/// `{"moved": true, "from_round": n, "in_user_id": "<uuid>"}`.
///
/// A missing or malformed id is `400` (`h2h.user_invalid`), a missing
/// reason `400` (`h2h.reason_required`). A player outside the elite
/// groups, relegated already, no round to swap before, or no substitute
/// is `409`.
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
  final rawUser = body['user_id'];
  final user = UserId.tryParse(rawUser is String ? rawUser : null);
  if (user is Err<UserId>) {
    return errorResponse(
      const AppError.validation(
        'h2h.user_invalid',
        'Field "user_id" must be a user id',
      ),
    );
  }
  final reason = body['reason'];
  if (reason is! String) {
    return errorResponse(
      const AppError.validation(
        'h2h.reason_required',
        'Field "reason" must be a text of 1 to 300 characters',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.h2hAbsenceDesk.relegate(
    principal: principal,
    userId: (user as Ok<UserId>).value,
    reason: reason,
  );

  return switch (result) {
    Ok<H2hSeatMove>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: {
        'moved': true,
        'from_round': value.fromRound,
        'in_user_id': value.inUser.value,
      },
    ),
    Err<H2hSeatMove>(:final error) => errorResponse(error),
  };
}
