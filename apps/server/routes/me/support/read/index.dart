import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /me/support/read` -- the caller has read support's answers
/// (migration 0187): they turn "read" for support and his unread count is
/// 0. Answers how many it marked; 0 before his first message.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.markMySupportRead(principal: principal);
  return switch (result) {
    Ok<int>(:final value) => Response.json(
      body: SupportCountDto(count: value).toJson(),
    ),
    Err<int>(:final error) => errorResponse(error),
  };
}
