import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:shared/shared.dart';

/// DELETE /groups/{id}/members/{userId} — a league's roster loses one member
/// (audit M-26):
///   * `me` — the caller leaves (command intent `LeaveGroup`); the owner
///     cannot leave (`409` `group.owner_cannot_leave`) and deletes the league
///     instead;
///   * a user id — the owner removes that member (`RemoveGroupMember`); a
///     member is refused `401` `group.not_owner`, someone not in the league
///     is `409` `group.member_not_found`.
///
/// `204` on success. A non-member is refused `401` `group.not_a_member`
/// whether or not the league exists. Both gates live in the use-cases; the
/// `/groups` subtree is already behind `bearerAuth`.
Future<Response> onRequest(
  RequestContext context,
  String id,
  String userId,
) async {
  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final Result<void> result = userId == 'me'
      ? await root.leaveGroup(principal: principal, groupId: id)
      : await root.removeGroupMember(
          principal: principal,
          groupId: id,
          memberUserId: userId,
        );

  return switch (result) {
    Ok<void>() => Response(statusCode: HttpStatus.noContent),
    Err<void>(:final error) => errorResponse(error),
  };
}
