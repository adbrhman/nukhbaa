import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/users` — browse platform users by an optional email-contains
/// `search`. Admin-only (gate inside `ListUsers`). `?limit=` clamps
/// server-side. Returns [UserListDto] (`200`); empty `users` is legitimate.
/// `405` on any non-GET method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final query = context.request.uri.queryParameters;
  final rawLimit = query['limit'];
  final limit = rawLimit == null ? null : int.tryParse(rawLimit);

  final result = await root.listUsers(
    principal: principal,
    search: query['search'],
    limit: limit,
  );

  return switch (result) {
    Ok<List<User>>(:final value) => Response.json(body: userListJson(value)),
    Err<List<User>>(:final error) => errorResponse(error),
  };
}
