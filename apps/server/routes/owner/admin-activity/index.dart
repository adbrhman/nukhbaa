import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

// NK300_10
/// `GET /owner/admin-activity` -- every change an admin made, the newest
/// first, with his name and the player or match it touched
/// (`OwnerAdminActivity`, script 300, migration 0224).
///
/// Anyone but an owner seat gets the owner gate's `404` (script 287).
/// `405` on any other method.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }
  final root = await context.read<Future<CompositionRoot>>();
  final OwnerAdminActivity? activity = root.ownerAdminActivity;
  if (activity == null) {
    return errorResponse(
      const AppError.transient(
        'owner.activity_unavailable',
        'The admins log is unavailable',
      ),
    );
  }
  final Result<List<AdminActivity>> listed = await activity.list(
    principal: context.read<AuthenticatedUser>(),
  );
  return switch (listed) {
    Ok<List<AdminActivity>>(:final value) => Response.json(
      body: AdminActivityLogDto(
        entries: <AdminActivityDto>[
          for (final AdminActivity line in value)
            AdminActivityDto(
              id: line.id,
              actorName: line.actorName,
              method: line.method,
              path: line.path,
              at: line.at,
              target: line.target,
              result: line.result,
            ),
        ],
      ).toJson(),
    ),
    Err<List<AdminActivity>>(:final error) => errorResponse(error),
  };
}
