import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/support_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `POST /admin/support/conversations/{id}/messages` `{"body": "..."}` --
/// an admin answers the player as "دعم نُخبة" (migration 0187). The player
/// gets a push when it is the first answer waiting for him.
///
/// Admin only, in the use-case.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final text = requireString(
    (bodyResult as Ok<Map<String, Object?>>).value,
    'body',
  );
  if (text is Err<String>) return errorResponse(text.error);
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.adminReplySupport(
    principal: principal,
    conversationId: id,
    text: (text as Ok<String>).value,
  );
  if (result is Ok<SupportMessageStored>) {
    notifySupportMessageLater(root, result.value);
  }
  return switch (result) {
    Ok<SupportMessageStored>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: supportMessageDto(value.message).toJson(),
    ),
    Err<SupportMessageStored>(:final error) => errorResponse(error),
  };
}
