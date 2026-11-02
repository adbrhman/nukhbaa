import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `PUT /admin/champions/{seasonId}/prize` -- sets the prize the month will
/// be crowned with (migration 0199, script 204): the automatic crowning
/// takes it, and a month left without one takes the previous month's.
/// Body: `{"prize": "150 ريال سعودي"}` (trimmed, 1 to 80 letters). Answers
/// `{"prize": "..."}`. Admin only.
///
/// Refusals: `400` for a blank or longer prize (`champion.prize_blank`,
/// `champion.prize_too_long`) or a malformed body; `409` for a month
/// already crowned (`champion.already_crowned`) or unknown
/// (`champion.month_not_found`); a non-admin `401`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final Object? prize = (bodyResult as Ok<Map<String, Object?>>).value['prize'];

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final setPrize = root.adminSetMonthPrize;
  if (setPrize == null) {
    return errorResponse(
      const AppError.transient(
        'champion.prize_unavailable',
        'The month prize is unavailable',
      ),
    );
  }
  final result = await setPrize(
    principal: principal,
    seasonId: id,
    prize: prize is String ? prize : null,
  );

  return switch (result) {
    Ok<String>(:final value) => Response.json(
      body: <String, Object?>{'prize': value},
    ),
    Err<String>(:final error) => errorResponse(error),
  };
}
