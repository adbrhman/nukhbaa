import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// PUT /me/display-name — lets the authenticated caller rename themselves
/// (`UpdateDisplayName`). Sibling to `GET /me`; inherits the same
/// `bearerAuth` middleware from `routes/me/_middleware.dart`, so
/// [AuthenticatedUser] is already in the context here. PUT (not PATCH) to
/// reuse the existing idempotent-full-resource-upsert transport verb
/// ([ApiTransport.putObject]) already used elsewhere in this client.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  return switch (bodyResult) {
    Err<Map<String, Object?>>(:final error) => errorResponse(error),
    Ok<Map<String, Object?>>(:final value) => _handle(context, value),
  };
}

Future<Response> _handle(
  RequestContext context,
  Map<String, Object?> body,
) async {
  final displayNameResult = requireString(body, 'display_name');
  if (displayNameResult is Err<String>) {
    return errorResponse(displayNameResult.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.updateDisplayName(
    principal: principal,
    displayName: (displayNameResult as Ok<String>).value,
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
        ),
      ).toJson(),
    ),
    Err<User>(:final error) => errorResponse(error),
  };
}
