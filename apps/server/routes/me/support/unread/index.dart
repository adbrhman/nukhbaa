import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /me/support/unread` -- how many of support's answers the caller has
/// not read (migration 0187): the badge on "تواصل مع المطوّر".
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.getMySupportUnread(principal: principal);
  return switch (result) {
    Ok<int>(:final value) => Response.json(
      body: SupportCountDto(count: value).toJson(),
    ),
    Err<int>(:final error) => errorResponse(error),
  };
}
