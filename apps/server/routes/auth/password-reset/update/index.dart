import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// POST /auth/password-reset/update.
///
/// The recovery access token is accepted only through Authorization.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final authorization = context.request.headers['authorization'];

  if (authorization == null || !authorization.startsWith('Bearer ')) {
    return errorResponse(
      const AppError.authorization(
        'auth.recovery_token_missing',
        'Password reset link is invalid or expired.',
      ),
    );
  }

  final token = authorization.substring('Bearer '.length).trim();

  if (token.isEmpty) {
    return errorResponse(
      const AppError.authorization(
        'auth.recovery_token_missing',
        'Password reset link is invalid or expired.',
      ),
    );
  }

  final bodyResult = await readJsonObject(context.request);

  return switch (bodyResult) {
    Err<Map<String, Object?>>(:final error) => errorResponse(error),
    Ok<Map<String, Object?>>(:final value) => _handle(context, value, token),
  };
}

Future<Response> _handle(
  RequestContext context,
  Map<String, Object?> body,
  String recoveryToken,
) async {
  final passwordResult = requireString(body, 'password');

  if (passwordResult is Err<String>) {
    return errorResponse(passwordResult.error);
  }

  final password = (passwordResult as Ok<String>).value;

  if (password.length < 8) {
    return errorResponse(
      const AppError.validation(
        'auth.password_too_short',
        'Password must be at least 8 characters.',
      ),
    );
  }

  final root = await context.read<Future<CompositionRoot>>();

  final result = await root.updatePassword(
    recoveryToken: recoveryToken,
    password: password,
  );

  return switch (result) {
    Ok<void>() => Response.json(
      body: const PasswordResetResponseDto(success: true).toJson(),
    ),
    Err<void>(:final error) => errorResponse(error),
  };
}
