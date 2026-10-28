import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/rate_limit.dart';
import 'package:server/http/support_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `/me/support/messages` -- the caller's own chat with Nukhbaa support
/// (migration 0187).
///
/// * `GET` -- a page of it, oldest first: the newest `?limit=` messages
///   (default 30, at most 100), or those before `?before=` (a message id).
///   Before his first message: no status and no messages.
/// * `POST` `{"body": "..."}` -- a message to support; his first opens the
///   conversation, one to a closed one reopens it. 60 an hour.
///
/// Only the caller's own: the conversation is found by his id, never by an
/// id from the request. Inherits `bearerAuth` from `routes/me`.
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
  final result = await root.getMySupportThread(
    principal: principal,
    beforeId: int.tryParse(query['before'] ?? ''),
    limit: int.tryParse(query['limit'] ?? ''),
  );
  return switch (result) {
    Ok<SupportThread>(:final value) => Response.json(
      body: supportThreadDto(value).toJson(),
    ),
    Err<SupportThread>(:final error) => errorResponse(error),
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
  final limited = limitPlayerAppend(PlayerAppend.supportMessage, principal);
  if (limited != null) return limited;

  final result = await root.sendSupportMessage(
    principal: principal,
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
