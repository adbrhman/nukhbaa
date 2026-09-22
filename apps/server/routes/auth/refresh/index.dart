/// POST /auth/refresh -- renews a session from its refresh token.
///
/// Public like /auth/login: the caller's access token has usually just
/// expired, so this route sits outside `bearerAuth`. The client calls it once
/// after a `401` and repeats the original request with the new token. A
/// spent or revoked refresh token is answered `400 auth.rejected`, never
/// `401`, so the client's renewal hook cannot recurse.
library;

import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
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
  final tokenResult = requireString(body, 'refresh_token');
  if (tokenResult is Err<String>) {
    return errorResponse(tokenResult.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final result = await root.refreshSession(
    refreshToken: (tokenResult as Ok<String>).value,
  );

  return switch (result) {
    Ok<IssuedSession>(:final value) => _sessionResponse(value),
    Err<IssuedSession>(:final error) => errorResponse(error),
  };
}

Response _sessionResponse(IssuedSession session) {
  final accessToken = session.accessToken;
  if (accessToken == null) {
    return errorResponse(
      const AppError.transient(
        'auth.malformed_response',
        'Supabase Auth returned no access token',
      ),
    );
  }
  return Response.json(
    body: AuthResponseDto(
      accessToken: accessToken,
      refreshToken: session.refreshToken,
      userId: null,
      email: null,
    ).toJson(),
  );
}
