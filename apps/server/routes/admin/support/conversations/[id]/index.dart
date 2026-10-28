import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/support_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `/admin/support/conversations/{id}` -- one player's conversation
/// (migration 0187).
///
/// * `GET` -- its line and a page of it, oldest first (`?before=`,
///   `?limit=` as for `GET /me/support/messages`).
/// * `PATCH` `{"status": "open" | "closed" | "archived"}`.
///
/// Admin only, in the use-cases. An id not on file is
/// `409 support.conversation_not_found`.
Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _read(context, id),
    HttpMethod.patch => _setStatus(context, id),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

Future<Response> _read(RequestContext context, String id) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final query = context.request.uri.queryParameters;
  final result = await root.adminGetSupportConversation(
    principal: principal,
    conversationId: id,
    beforeId: int.tryParse(query['before'] ?? ''),
    limit: int.tryParse(query['limit'] ?? ''),
  );
  return switch (result) {
    Ok<SupportConversationPage>(:final value) => Response.json(
      body: SupportConversationPageDto(
        conversation: supportConversationDto(value.summary),
        thread: supportThreadDto(value.thread),
      ).toJson(),
    ),
    Err<SupportConversationPage>(:final error) => errorResponse(error),
  };
}

Future<Response> _setStatus(RequestContext context, String id) async {
  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final status = requireString(
    (bodyResult as Ok<Map<String, Object?>>).value,
    'status',
  );
  if (status is Err<String>) return errorResponse(status.error);
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.adminSetSupportStatus(
    principal: principal,
    conversationId: id,
    status: (status as Ok<String>).value,
  );
  return switch (result) {
    Ok<void>() => Response.json(
      body: SupportStatusDto(status: status.value).toJson(),
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
