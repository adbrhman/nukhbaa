import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `GET /admin/user-stats` — the platform-wide user counts (Database ADR
/// §3, `identity.users`): total registered users plus the active/suspended
/// split, computed as a single server-side aggregate over the WHOLE table.
/// Distinct from `GET /admin/users`, which is a bounded browse page for
/// finding one user to sanction and must never be read as a total. Admin
/// only: the gate lives in the use-case, as for every admin read; a
/// non-admin is refused `401 auth.insufficient_role`. `405` on any non-GET
/// method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.adminGetUserStats(principal: principal);

  return switch (result) {
    Ok<UserCounts>(:final value) => Response.json(
      body: UserStatsDto(
        total: value.total,
        active: value.active,
        suspended: value.suspended,
      ).toJson(),
    ),
    Err<UserCounts>(:final error) => errorResponse(error),
  };
}
