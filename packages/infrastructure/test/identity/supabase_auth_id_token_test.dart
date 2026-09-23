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

SupabaseAuthClient _client(List<http.Request> captured) => SupabaseAuthClient(
  config: _config(),
  httpClient: MockClient((request) async {
    captured.add(request);
    return http.Response(
      jsonEncode({
        'access_token': 'g-access',
        'refresh_token': 'g-refresh',
        'user': {'id': 'u-1', 'email': 'a@gmail.com'},
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }),
);

void main() {
  test('signs in through grant_type=id_token with the provider and the '
      'token', () async {
    final captured = <http.Request>[];

    final result = await _client(
      captured,
    ).signInWithIdToken(provider: 'google', idToken: 'google-id-token');

    final request = captured.single;
    expect(request.url.path, endsWith('/token'));
    expect(request.url.queryParameters['grant_type'], 'id_token');
    expect(jsonDecode(request.body), {
      'provider': 'google',
      'id_token': 'google-id-token',
    });
    final session = (result as Ok<SupabaseSession>).value;
    expect(session.accessToken, 'g-access');
    expect(session.refreshToken, 'g-refresh');
  });

  test('the use-case hands a trimmed Google token through the gateway and '
      'returns the session', () async {
    final captured = <http.Request>[];
    final useCase = SignInWithGoogle(SupabaseAuthGateway(_client(captured)));

    final result = await useCase(idToken: '  google-id-token  ');

    final sent = jsonDecode(captured.single.body) as Map<String, Object?>;
    expect(sent['id_token'], 'google-id-token');
    final session = (result as Ok<IssuedSession>).value;
    expect(session.accessToken, 'g-access');
    expect(session.refreshToken, 'g-refresh');
  });

  test('a blank token never reaches the identity provider', () async {
    final captured = <http.Request>[];
    final useCase = SignInWithGoogle(SupabaseAuthGateway(_client(captured)));

    final result = await useCase(idToken: '   ');

    expect(
      (result as Err<IssuedSession>).error.code,
      'auth.google_token_required',
    );
    expect(captured, isEmpty);
  });
}
