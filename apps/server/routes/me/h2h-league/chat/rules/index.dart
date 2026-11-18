import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /me/h2h-league/chat/rules` -- the caller accepts the chat rules
/// (migration 0216); until he does he cannot write. Saying yes again
/// changes nothing.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.h2hChat.acceptRules(principal: principal);
  return switch (result) {
    Ok<void>() => Response.json(body: const H2hChatAckDto().toJson()),
    Err<void>(:final error) => errorResponse(error),
  };
}
