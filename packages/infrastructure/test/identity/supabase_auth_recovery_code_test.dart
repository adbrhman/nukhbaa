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

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  test('the code of a reset e-mail is verified through POST /verify with '
      'type recovery, and its access token is the recovery token', () async {
    final captured = <http.Request>[];
    final gateway = SupabaseAuthGateway(
      SupabaseAuthClient(
        config: _config(),
        httpClient: MockClient((request) async {
          captured.add(request);
          return _json({
            'access_token': 'recovery-access',
            'refresh_token': 'r',
            'user': {'id': 'u-1', 'email': 'a@example.com'},
          }, 200);
        }),
      ),
    );

    final result = await gateway.verifyRecoveryCode(
      email: 'a@example.com',
      code: '123456',
    );

    final request = captured.single;
    expect(request.method, 'POST');
    expect(request.url.path, endsWith('/verify'));
    expect(jsonDecode(request.body), {
      'type': 'recovery',
      'email': 'a@example.com',
      'token': '123456',
    });
    expect((result as Ok<String>).value, 'recovery-access');
  });

  test(
    'a wrong or expired code is a validation error the player can read',
    () async {
      final gateway = SupabaseAuthGateway(
        SupabaseAuthClient(
          config: _config(),
          httpClient: MockClient(
            (_) async => _json({
              'code': 403,
              'error_code': 'otp_expired',
              'msg': 'Token has expired or is invalid',
            }, 403),
          ),
        ),
      );

      final result = await gateway.verifyRecoveryCode(
        email: 'a@example.com',
        code: '000000',
      );

      final error = (result as Err<String>).error;
      expect(error.kind, ErrorKind.validation);
      expect(error.code, 'auth.recovery_code_invalid');
      expect(error.message, contains('الرمز'));
    },
  );
}
