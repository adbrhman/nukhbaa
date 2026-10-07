import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/group_invitation_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /groups/invitations` -- the caller's own invitations to friends'
/// leagues (migration 0097), newest first, whatever their status:
/// `GroupInvitationsDto`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.listMyGroupInvitations(principal: principal);
  return switch (result) {
    Ok<List<GroupInvitation>>(:final value) => Response.json(
      body: groupInvitationsToDto(value).toJson(),
    ),
    Err<List<GroupInvitation>>(:final error) => errorResponse(error),
  };
}
