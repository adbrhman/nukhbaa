import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /duels/challenges/{id}/cancel` -- the challenger closes an open
/// challenge (migration 0090). Duels already accepted from it stay.
/// Answers `200` `{"status": "cancelled"}`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.cancelDuelChallenge(
    principal: principal,
    challengeId: id,
  );

  return switch (result) {
    Ok<void>() => Response.json(body: {'status': 'cancelled'}),
    Err<void>(:final error) => errorResponse(error),
  };
}
