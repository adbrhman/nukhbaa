import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/h2h/excusals` -- an admin takes a round out of the absence
/// count (the app was down; NK183, migration 0189). Body:
/// `{"round_id": "<uuid>", "reason": "<1..300 characters>"}`. The round is
/// neither an absence nor a presence for anybody from then on; a swap
/// already made stays. Answers `200` `{"changed": true}`, or
/// `{"changed": false}` when it was excused already. The excusal is written
/// to the admin log.
///
/// A missing or malformed id is `400` (`h2h.round_invalid`), a missing
/// reason `400` (`h2h.reason_required`). A round of neither this month nor
/// the month before, or one not started, is `409`.
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
  final rawRound = body['round_id'];
  final round = H2hRoundId.tryParse(rawRound is String ? rawRound : null);
  if (round is Err<H2hRoundId>) {
    return errorResponse(
      const AppError.validation(
        'h2h.round_invalid',
        'Field "round_id" must be a round id',
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

  final result = await root.h2hAbsenceDesk.excuse(
    principal: principal,
    roundId: (round as Ok<H2hRoundId>).value,
    reason: reason,
  );

  return switch (result) {
    Ok<bool>(:final value) => Response.json(body: {'changed': value}),
    Err<bool>(:final error) => errorResponse(error),
  };
}
