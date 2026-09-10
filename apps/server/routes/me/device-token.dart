import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// `POST /me/device-token` -- register the calling device for push delivery.
///
/// Body: `{ "token": string, "platform": "android" | "ios" }`. The owner comes
/// from the verified token, never the body (Security ADR §2).
///
/// Idempotent: the app calls this on every launch and on every FCM token
/// refresh, and the adapter upserts by token (migration 0039), so a repeat is
/// a no-op re-confirmation and a handset that changed hands is rebound rather
/// than duplicated.
///
/// Inherits `bearerAuth` from `routes/me/_middleware.dart`, so an
/// unauthenticated request never arrives here.
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

  final platform = requireString(body, 'platform');
  if (platform is Err<String>) {
    return errorResponse(platform.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final principal = context.read<AuthenticatedUser>();

  final result = await root.registerDeviceToken(
    principal: principal,
    token: (token as Ok<String>).value,
    platform: (platform as Ok<String>).value,
  );

  return switch (result) {
    Ok<void>() => Response.json(
      body: const DeviceTokenAckDto(registered: true).toJson(),
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
