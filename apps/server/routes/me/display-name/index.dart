import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/avatar_url.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// PUT /me/display-name -- the one-time choice of a display name.
///
/// A display name is chosen once and is immutable from then on. Registration
/// makes that choice; an account created without it (a first Google sign-in)
/// makes it here, and `UpdateDisplayName` refuses every later attempt with
/// `identity.display_name_immutable`. Answers the caller's `MeResponseDto`,
/// like the avatar routes. Inherits `bearerAuth` from
/// `routes/me/_middleware.dart`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final name = requireString(body, 'display_name');
  if (name is Err<String>) {
    return errorResponse(name.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();
  final result = await root.updateDisplayName(
    principal: principal,
    displayName: (name as Ok<String>).value,
  );

  return switch (result) {
    Ok<User>(:final value) => Response.json(
      body: MeResponseDto(
        user: AuthenticatedUserDto(
          userId: value.id.value,
          role: value.role.name,
          status: value.status.name,
          email: value.email,
          displayName: value.displayName,
          avatarUrl: avatarUrlFor(value),
        ),
      ).toJson(),
    ),
    Err<User>(:final error) => errorResponse(error),
  };
}
