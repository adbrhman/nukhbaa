import 'dart:async';
import 'dart:io';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:shared/shared.dart';

/// POST /auth/register — creates a new email/password account, proxying to
/// Supabase Auth server-side so no client ever holds a Supabase key.
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
  final passwordResult = requireString(body, 'password');
  if (passwordResult is Err<String>) {
    return errorResponse(passwordResult.error);
  }
  final displayNameResult = requireString(body, 'display_name');
  if (displayNameResult is Err<String>) {
    return errorResponse(displayNameResult.error);
  }

  final root = await context.read<Future<CompositionRoot>>();
  final result = await root.register(
    email: (emailResult as Ok<String>).value,
    password: (passwordResult as Ok<String>).value,
    displayName: (displayNameResult as Ok<String>).value,
  );

  if (result is Ok<IssuedSession>) {
    unawaited(_alertAdmins(root));
  }

  return switch (result) {
    Ok<IssuedSession>(:final value) => _sessionResponse(value),
    Err<IssuedSession>(:final error) => errorResponse(error),
  };
}

/// Best-effort admin alert: the signup already succeeded, so a failure here
/// is logged and never reaches the caller or the zone.
Future<void> _alertAdmins(CompositionRoot root) async {
  try {
    final result = await root.notifyNewUserRegistered();
    if (result is Err<void>) {
      // ignore: avoid_print
      print('admin new-user push failed: ${result.error.code}');
    }
  } on Object catch (error) {
    // ignore: avoid_print
    print('admin new-user push threw: $error');
  }
}

Response _sessionResponse(IssuedSession session) {
  if (session.accessToken == null || session.emailConfirmationRequired) {
    return errorResponse(
      const AppError.validation(
        'auth.confirmation_required',
        'Please check your email to confirm your account, then sign in.',
      ),
    );
  }
  return Response.json(
    body: AuthResponseDto(
      accessToken: session.accessToken!,
      // IssuedSession does not carry these; the client fetches them via /me.
      userId: null,
      email: null,
      refreshToken: session.refreshToken,
    ).toJson(),
  );
}
