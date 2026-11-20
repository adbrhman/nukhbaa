import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/h2h_chat_dto_mapper.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/owner_switch_stop.dart';
import 'package:server/http/rate_limit.dart';
import 'package:shared/shared.dart';

/// `/me/h2h-league/chat` -- the chat of the caller's own head-to-head
/// group (migration 0216, script 281).
///
/// * `GET` -- the newest `?limit=` messages (default 50, at most 100),
///   oldest first, or those after `?after=` (a message id). Hidden messages
///   and blocked players are left out; before he holds a seat, no group.
/// * `POST` `{"body": "..."}` -- a message to the group, 1 to 500
///   characters; he must have accepted the rules and not be muted. 60 an
///   hour.
///
/// Only the caller's own group: it is found by his id, never by an id from
/// the request. Inherits `bearerAuth` from `routes/me`.
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => _read(context),
    HttpMethod.post => _send(context),
    _ => Response(statusCode: HttpStatus.methodNotAllowed),
  };
}

Future<Response> _read(RequestContext context) async {
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final query = context.request.uri.queryParameters;
  final result = await root.h2hChat.page(
    principal: principal,
    afterId: int.tryParse(query['after'] ?? ''),
    limit: int.tryParse(query['limit'] ?? ''),
  );
  return switch (result) {
    Ok<H2hChatPage>(:final value) => Response.json(
      body: h2hChatPageDto(value, principal.userId).toJson(),
    ),
    Err<H2hChatPage>(:final error) => errorResponse(error),
  };
}

Future<Response> _send(RequestContext context) async {
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
  final limited = limitPlayerAppend(PlayerAppend.h2hChatMessage, principal);
  if (limited != null) return limited;
  // NK291_04
  // The owners' stop on the chat (script 291).
  final Response? paused = await ownerSwitchStop(root, OwnerSwitch.chat);
  if (paused != null) return paused;

  final result = await root.h2hChat.send(
    principal: principal,
    text: (text as Ok<String>).value,
  );
  return switch (result) {
    Ok<H2hChatMessage>(:final value) => Response.json(
      statusCode: HttpStatus.created,
      body: h2hChatMessageDto(value, principal.userId).toJson(),
    ),
    Err<H2hChatMessage>(:final error) => errorResponse(error),
  };
}
