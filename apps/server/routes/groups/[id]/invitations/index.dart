import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/rate_limit.dart';
import 'package:shared/shared.dart';

/// `POST /groups/{id}/invitations` -- a member invites a player found by
/// name to the friends' league (migration 0097).
///
/// Body: `{ "user_id": string }`. Answers `200` `{ "invited": bool }`:
/// `true` when invited now (the player is told), `false` when they were
/// invited to this league before. `401` `group.not_a_member` for anyone
/// outside the league; `409` `group.already_member` / `group.invite_self`.
/// A player sends at most 30 new invitations in 24 hours (`409`
/// `social.daily_limit`, audit M-20); a repeat that tells nobody is not
/// counted.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final limited = limitPlayerReach(PlayerReach.groupInvite, principal);
  if (limited != null) {
    return limited;
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final userId = requireString(
    (bodyResult as Ok<Map<String, Object?>>).value,
    'user_id',
  );
  if (userId is Err<String>) {
    return errorResponse(userId.error);
  }

  final result = await root.inviteToGroup(
    principal: principal,
    groupId: id,
    inviteeUserId: (userId as Ok<String>).value,
  );
  if (result case Ok<bool>(value: true)) {
    countPlayerReach(PlayerReach.groupInvite, principal);
  }
  return switch (result) {
    Ok<bool>(:final value) => Response.json(body: {'invited': value}),
    Err<bool>(:final error) => errorResponse(error),
  };
}
