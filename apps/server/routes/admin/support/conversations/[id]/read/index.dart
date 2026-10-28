import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /admin/support/conversations/{id}/read` -- an admin has read the
/// player's messages (migration 0187). Answers how many it marked.
///
/// Admin only, in the use-case.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.adminMarkSupportRead(
    principal: principal,
    conversationId: id,
  );
  return switch (result) {
    Ok<int>(:final value) => Response.json(
      body: SupportCountDto(count: value).toJson(),
    ),
    Err<int>(:final error) => errorResponse(error),
  };
}
