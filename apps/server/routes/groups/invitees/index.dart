import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/group_invitation_dto_mapper.dart';
import 'package:shared/shared.dart';

/// `GET /groups/invitees?q=NAME` -- players to invite to a friends' league
/// by name (migration 0097).
///
/// Answers `200` with `GroupInviteesDto`: active players whose display name
/// contains `q`, exact matches first, never the caller. A query shorter
/// than two characters answers an empty list. The `/groups` subtree is
/// behind `bearerAuth`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.searchGroupInvitees(
    principal: principal,
    query: context.request.uri.queryParameters['q'] ?? '',
  );

  return switch (result) {
    Ok<List<GroupInvitee>>(:final value) => Response.json(
      body: groupInviteesToDto(value).toJson(),
    ),
    Err<List<GroupInvitee>>(:final error) => errorResponse(error),
  };
}
