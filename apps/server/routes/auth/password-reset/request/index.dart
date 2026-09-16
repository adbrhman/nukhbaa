import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// POST /auth/password-reset/request.
///
/// A valid request returns a generic acknowledgement so the endpoint does not
/// reveal whether an account exists.
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
  final emailResult = requireString(body, 'email');

  if (emailResult is Err<String>) {
    return errorResponse(emailResult.error);
  }

  final email = (emailResult as Ok<String>).value.trim();

  if (email.isEmpty || !email.contains('@')) {
    return errorResponse(
      const AppError.validation(
        'auth.email_invalid',
        'Please enter a valid email address.',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();

  final result = await root.requestPasswordReset(email: email);

  return switch (result) {
    Ok<void>() => Response.json(
      body: const PasswordResetResponseDto(success: true).toJson(),
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
