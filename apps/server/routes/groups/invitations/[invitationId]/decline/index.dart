import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// `POST /groups/invitations/{invitationId}/decline` -- the invited player
/// declines: nobody is told (migration 0097).
///
/// Answers `200` `{ "status": string }`, the invitation's status after the
/// answer; one already answered keeps its answer. `409`
/// `group.invitation_not_found` for an unknown invitation or someone
/// else's.
Future<Response> onRequest(RequestContext context, String invitationId) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.respondToGroupInvitation(
    principal: principal,
    invitationId: invitationId,
    accept: false,
  );
  return switch (result) {
    Ok<GroupInvitationStatus>(:final value) => Response.json(
      body: {'status': value.wireValue},
    ),
    Err<GroupInvitationStatus>(:final error) => errorResponse(error),
  };
}
