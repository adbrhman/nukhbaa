import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:infrastructure/infrastructure.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

AuthConfig _config(String key) =>
    (AuthConfig.fromEnv({
              'NUKHBA_SUPABASE_PROJECT_REF': 'abcdefghijklmnop',
              'NUKHBA_SUPABASE_ANON_KEY': key,
            })
            as Ok<AuthConfig>)
        .value;

Future<http.BaseRequest> _signInWith(String key) async {
  http.BaseRequest? captured;
  final client = SupabaseAuthClient(
    config: _config(key),
    httpClient: MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'error': 'invalid_grant'}),
        400,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  await client.signIn(email: 'user@example.com', password: 'secret-123');
  return captured!;
}

void main() {
  test('a publishable key travels in apikey only', () async {
    const key = 'sb_publishable_abc123DEF456';
    final request = await _signInWith(key);

    expect(request.headers['apikey'], key);
    expect(request.headers.containsKey('authorization'), isFalse);
  });

  test('a legacy anon JWT keeps its bearer header', () async {
    const key = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.c2lnbmF0dXJl';
    final request = await _signInWith(key);

    expect(request.headers['apikey'], key);
    expect(request.headers['authorization'], 'Bearer $key');
  });
}
