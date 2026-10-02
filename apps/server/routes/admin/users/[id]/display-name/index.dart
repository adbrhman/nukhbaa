import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_dto_mapper.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /admin/users/{id}/display-name` -- an admin renames a player
/// (`AdminRenameUser`). Body: [AdminRenameUserRequestDto] (`display_name`,
/// `reason`). Answers the renamed account as a [UserSummaryDto] (`200`).
///
/// A name another player holds is `400` `identity.display_name_taken`; a
/// missing reason `400` `admin.rename_reason_required`; an unknown account
/// `409` `admin.user_not_found`; a non-admin `401` `auth.insufficient_role`.
/// `405` on any non-POST method. Behind `bearerAuth` like all of `/admin`.
Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final dto = AdminRenameUserRequestDto.fromJson(
    (bodyResult as Ok<Map<String, Object?>>).value,
  );

  final result = await root.adminRenameUser(
    principal: principal,
    targetUserId: id,
    displayName: dto.displayName,
    reason: dto.reason,
  );

  return switch (result) {
    Ok<User>(:final value) => Response.json(
      body: userSummaryToDto(value).toJson(),
    ),
    Err<User>(:final error) => errorResponse(error),
  };
}
