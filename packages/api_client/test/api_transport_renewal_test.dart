import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  late String token;
  late List<String> seen;
  late int renewals;
  late int signOuts;

  setUp(() {
    token = 'stale';
    seen = <String>[];
    renewals = 0;
    signOuts = 0;
  });

  ApiTransport build(SessionRenewal outcome) => ApiTransport(
    baseUri: Uri.parse('https://api.test.example/'),
    httpClient: MockClient((request) async {
      seen.add('${request.url.path} ${request.headers['authorization']}');
      return request.headers['authorization'] == 'Bearer fresh'
          ? http.Response(jsonEncode({'ok': true}), 200)
          : http.Response(
              jsonEncode({
                'schema_version': 1,
                'code': 'auth.invalid_token',
                'message': 'The access token has expired.',
              }),
              401,
              headers: const {'content-type': 'application/json'},
            );
    }),
    tokenProvider: () async => token,
    requestTimeout: null,
    renewSession: () async {
      renewals++;
      if (outcome == SessionRenewal.renewed) {
        token = 'fresh';
      }
      return outcome;
    },
    onUnauthorized: () async {
      signOuts++;
    },
  );

  Future<Result<bool>> me(ApiTransport transport) =>
      transport.getObject<bool>('/me', parse: (json) => json['ok']! as bool);

  test('a 401 renews once and repeats the call with the new token', () async {
    final result = await me(build(SessionRenewal.renewed));

    expect(result, isA<Ok<bool>>());
    expect(renewals, 1);
    expect(signOuts, 0);
    expect(seen, ['/me Bearer stale', '/me Bearer fresh']);
  });

  test('a refused renewal ends the session', () async {
    final result = await me(build(SessionRenewal.rejected));

    expect((result as Err<bool>).error.kind, ErrorKind.authorization);
    expect(renewals, 1);
    expect(signOuts, 1);
    expect(seen, hasLength(1));
  });

  test(
    'an unreachable renewal keeps the session and fails retryably',
    () async {
      final result = await me(build(SessionRenewal.unavailable));

      expect((result as Err<bool>).error.kind, ErrorKind.transient);
      expect(signOuts, 0);
      expect(seen, hasLength(1));
    },
  );

  test('auth routes are never renewed, so a renewal cannot recurse', () async {
    await build(SessionRenewal.renewed).postObject<bool>(
      '/auth/refresh',
      body: {'refresh_token': 'r'},
      parse: (json) => json['ok']! as bool,
    );

    expect(renewals, 0);
    expect(signOuts, 1);
  });
}
