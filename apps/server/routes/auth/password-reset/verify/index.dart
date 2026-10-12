import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/error_envelope.dart';
import 'package:server/http/json_body.dart';
import 'package:server/http/rate_limit.dart';
import 'package:shared/shared.dart';

/// POST /auth/password-reset/verify.
///
/// Trades the one-time code of the reset e-mail (`{"email", "code"}`) for
/// the recovery token that `POST /auth/password-reset/update` takes, so a
/// player resets the password inside the app instead of opening the web
/// build from the e-mail's link. Five codes per address in 15 minutes.
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

/// A code as GoTrue sends it: 6 digits by default, up to 10 when the
/// project's e-mail OTP length is raised.
final RegExp _codePattern = RegExp(r'^\d{6,10}$');

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

  final codeResult = requireString(body, 'code');
  if (codeResult is Err<String>) {
    return errorResponse(codeResult.error);
  }
  final code = (codeResult as Ok<String>).value.replaceAll(RegExp(r'\s'), '');
  if (!_codePattern.hasMatch(code)) {
    return errorResponse(
      const AppError.validation(
        'auth.recovery_code_format',
        'اكتب الرمز كما وصلك في البريد (أرقام فقط).',
      ),
    );
  }

  final limited = limitAuthAttempt(AuthAttempt.passwordResetCode, email);
  if (limited != null) {
    return limited;
  }

  final root = await context.read<Future<CompositionRoot>>();
  final result = await root.verifyRecoveryCode(email: email, code: code);

  return switch (result) {
    Ok<String>(:final value) => Response.json(
      body: PasswordResetCodeResponseDto(recoveryToken: value).toJson(),
    ),
    Err<String>(:final error) => errorResponse(error),
  };
}
