// Audit M-17: every GoTrue refusal used to reach the player as one generic
// line. The code stays `auth.rejected` (callers branch on it) but the
// message now says what went wrong, in Arabic, so the app shows it as it is.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

AuthConfig _config() =>
    (AuthConfig.fromEnv({
              'NUKHBA_SUPABASE_PROJECT_REF': 'abcdefghijklmnop',
              'NUKHBA_SUPABASE_ANON_KEY': 'sb_publishable_abc123DEF456',
            })
            as Ok<AuthConfig>)
        .value;

SupabaseAuthClient _answering(Map<String, Object?> body, int status) =>
    SupabaseAuthClient(
      config: _config(),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(body),
          status,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

Future<AppError> _signIn(Map<String, Object?> body, [int status = 400]) async {
  final result = await _answering(
    body,
    status,
  ).signIn(email: 'a@example.com', password: 'secret-123');
  return (result as Err<SupabaseSession>).error;
}

Future<AppError> _signUp(Map<String, Object?> body, [int status = 422]) async {
  final result = await _answering(
    body,
    status,
  ).signUp(email: 'a@example.com', password: 'secret-123');
  return (result as Err<SupabaseSession>).error;
}

void main() {
  test('a wrong password says so, still as auth.rejected', () async {
    final error = await _signIn({
      'error_code': 'invalid_credentials',
      'msg': 'Invalid login credentials',
    });
    expect(error.code, 'auth.rejected');
    expect(error.kind, ErrorKind.validation);
    expect(error.message, 'البريد أو كلمة المرور غير صحيحة.');
  });

  test('an older GoTrue without error_code is read from its message', () async {
    final error = await _signIn({
      'error': 'invalid_grant',
      'error_description': 'Invalid login credentials',
    });
    expect(error.message, 'البريد أو كلمة المرور غير صحيحة.');
  });

  test('an unconfirmed email is told to open the confirmation', () async {
    final error = await _signIn({
      'error_code': 'email_not_confirmed',
      'msg': 'Email not confirmed',
    });
    expect(error.message, contains('افتح رسالة التأكيد'));
  });

  test('a taken email, a weak password and a bad address on sign-up', () async {
    expect(
      (await _signUp({
        'error_code': 'user_already_exists',
        'msg': 'User already registered',
      })).message,
      contains('مسجّل من قبل'),
    );
    expect(
      (await _signUp({
        'error_code': 'weak_password',
        'msg': 'Password should be at least 6 characters.',
      })).message,
      contains('كلمة المرور ضعيفة'),
    );
    expect(
      (await _signUp({
        'error_code': 'email_address_invalid',
        'msg': 'Email address "x" is invalid',
      })).message,
      contains('صيغة البريد'),
    );
  });

  test('an unknown refusal keeps the message GoTrue sent', () async {
    final error = await _signIn({'msg': 'Something new'});
    expect(error.code, 'auth.rejected');
    expect(error.message, 'Something new');
  });

  test('a spent refresh token is not called a bad email', () async {
    final result = await _answering({
      'error': 'invalid_grant',
      'error_description': 'Invalid Refresh Token: Already Used',
    }, 400).refresh(refreshToken: 'spent');
    final error = (result as Err<SupabaseSession>).error;
    expect(error.code, 'auth.rejected');
    expect(error.message, isNot(contains('البريد')));
  });
}
