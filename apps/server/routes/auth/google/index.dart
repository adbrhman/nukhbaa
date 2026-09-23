/// POST /auth/google -- signs in (or signs up) with a Google ID token.
///
/// Public like /auth/login. The device's Google account picker mints the ID
/// token for the project's Web OAuth client; Supabase Auth verifies it,
/// creates the account on first use and links it to an existing account
/// with the same verified email.
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
  final tokenResult = requireString(body, 'id_token');
  if (tokenResult is Err<String>) {
    return errorResponse(tokenResult.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final result = await root.signInWithGoogle(
    idToken: (tokenResult as Ok<String>).value,
  );

  return switch (result) {
    Ok<IssuedSession>(:final value) => _sessionResponse(value),
    // The provider's own wording ("Provider is not enabled", "Invalid
    // audience", ...) means nothing to a user; one Arabic sentence does.
    Err<IssuedSession>(:final error) =>
      error.kind == ErrorKind.validation
          ? errorResponse(
              const AppError.validation(
                'auth.google_rejected',
                'تعذّر الدخول بحساب Google. حاول مرة أخرى.',
              ),
            )
          : errorResponse(error),
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
