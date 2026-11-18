import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /me/h2h-league/chat/read` -- the caller has read his group's chat
/// up to its newest message (migration 0216): his unread count is 0.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.h2hChat.markRead(principal: principal);
  return switch (result) {
    Ok<void>() => Response.json(body: const H2hChatAckDto().toJson()),
    Err<void>(:final error) => errorResponse(error),
  };
}
