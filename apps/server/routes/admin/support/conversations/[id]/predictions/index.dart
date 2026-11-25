import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/support_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /admin/support/conversations/{id}/predictions` `{"reason": "..."}`
/// -- the owner reads the conversation's player's predictions of the matches
/// not yet started (script 261, migration 0208): the one reading of a
/// prediction before its kickoff, by anyone. A `POST` for its body; it
/// writes nothing (decided 2026-11-25, script 327): no message to the
/// player, no push, no audit row, and the player need not have written
/// first.
///
/// Owner only, in the use-case (either seat): any other caller is refused
/// `auth.insufficient_role`. A blank or too long reason is
/// `400 support.peek_reason_invalid`; an id not on file is
/// `409 support.conversation_not_found`. Any other method is `405`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final reason = (bodyResult as Ok<Map<String, Object?>>).value['reason'];
  final root = await context.read<Future<CompositionRoot>>();
  final peek = root.supportPeekPredictions;
  if (peek == null) {
    return errorResponse(
      const AppError.transient(
        'support.peek_unavailable',
        'Support cannot read predictions on this server',
      ),
    );
  }
  final result = await peek(
    principal: context.read<AuthenticatedUser>(),
    conversationId: id,
    reason: reason is String ? reason : null,
  );
  return switch (result) {
    Ok<SupportPredictionsPeek>(:final value) => Response.json(
      body: supportPredictionsPeekDto(value).toJson(),
    ),
    Err<SupportPredictionsPeek>(:final error) => errorResponse(error),
  };
}
