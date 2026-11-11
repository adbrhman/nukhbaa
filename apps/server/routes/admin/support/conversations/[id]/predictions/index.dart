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
/// -- support reads the conversation's player's predictions of the matches
/// not yet started (script 261, migration 0208): the one reading of a
/// prediction before its kickoff, by anyone. A `POST`, as it writes: the
/// audit row (`support_predictions_viewed`) and the message that tells the
/// player, who gets a push as for any support answer.
///
/// Admin only, in the use-case. A blank or too long reason is
/// `400 support.peek_reason_invalid`; an id not on file is
/// `409 support.conversation_not_found`; a conversation the player has not
/// written in (among its last 50 messages) is
/// `409 support.peek_needs_player_message`. Any other method is `405`.
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
  if (result is Ok<SupportPredictionsPeek>) {
    notifySupportMessageLater(root, result.value.notice);
  }
  return switch (result) {
    Ok<SupportPredictionsPeek>(:final value) => Response.json(
      body: supportPredictionsPeekDto(value).toJson(),
    ),
    Err<SupportPredictionsPeek>(:final error) => errorResponse(error),
  };
}
