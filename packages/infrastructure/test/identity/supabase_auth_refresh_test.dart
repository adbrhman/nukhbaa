import 'dart:convert';

import 'package:application/application.dart';
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
  test('renews through grant_type=refresh_token and returns the rotated '
      'pair', () async {
    final captured = <http.Request>[];
    final client = SupabaseAuthClient(
      config: _config(),
      httpClient: MockClient((request) async {
        captured.add(request);
        return _json({
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'user': {'id': 'u-1', 'email': 'a@example.com'},
        }, 200);
      }),
    );

    final result = await client.refresh(refreshToken: 'old-refresh');

    final request = captured.single;
    expect(request.url.path, endsWith('/token'));
    expect(request.url.queryParameters['grant_type'], 'refresh_token');
    expect(jsonDecode(request.body), {'refresh_token': 'old-refresh'});
    final session = (result as Ok<SupabaseSession>).value;
    expect(session.accessToken, 'new-access');
    expect(session.refreshToken, 'new-refresh');
  });

  test('a spent refresh token is a validation rejection, not an '
      'authorization failure', () async {
    final client = SupabaseAuthClient(
      config: _config(),
      httpClient: MockClient(
        (_) async => _json({
          'error': 'invalid_grant',
          'error_description': 'Invalid Refresh Token: Already Used',
        }, 400),
      ),
    );

    final result = await client.refresh(refreshToken: 'spent');

    final error = (result as Err<SupabaseSession>).error;
    expect(error.kind, ErrorKind.validation);
    expect(error.code, 'auth.rejected');
  });

  test('the gateway hands the renewed pair to the application', () async {
    final gateway = SupabaseAuthGateway(
      SupabaseAuthClient(
        config: _config(),
        httpClient: MockClient(
          (_) async => _json({
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
          }, 200),
        ),
      ),
    );

    final result = await RefreshSession(gateway)(refreshToken: ' old ');

    final session = (result as Ok<IssuedSession>).value;
    expect(session.accessToken, 'new-access');
    expect(session.refreshToken, 'new-refresh');
    expect(session.emailConfirmationRequired, isFalse);
  });
}
