import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /me/device-token/remove` -- unbind this device from the caller's
/// pushes at sign-out (audit M-05).
///
/// Body: `{ "token": string }`. Only the caller's own row is removed (the
/// owner comes from the verified token, never the body): a phone that has
/// since been registered by another player keeps his. A token not on file
/// is not an error -- the answer is the same `registered: false`.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final bodyResult = await readJsonObject(context.request);
  if (bodyResult is Err<Map<String, Object?>>) {
    return errorResponse(bodyResult.error);
  }
  final body = (bodyResult as Ok<Map<String, Object?>>).value;

  final token = requireString(body, 'token');
  if (token is Err<String>) {
    return errorResponse(token.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.registerDeviceToken.unregister(
    principal: principal,
    token: (token as Ok<String>).value,
  );

  return switch (result) {
    Ok<void>() => Response.json(
      body: const DeviceTokenAckDto(registered: false).toJson(),
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
