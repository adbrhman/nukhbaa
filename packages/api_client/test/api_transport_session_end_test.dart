import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// A `401` that refuses one action leaves the session alone; only a `401`
/// about the credential itself renews it, and ends it when renewal fails.
void main() {
  late int renewals;
  late int signOuts;

  setUp(() {
    renewals = 0;
    signOuts = 0;
  });

  http.Response refusal(String? code) => http.Response(
    code == null
        ? ''
        : jsonEncode({'schema_version': 1, 'code': code, 'message': 'refused'}),
    401,
    headers: const {'content-type': 'application/json'},
  );

  ApiTransport build(String? code) => ApiTransport(
    baseUri: Uri.parse('https://api.test.example/'),
    httpClient: MockClient((request) async => refusal(code)),
    tokenProvider: () async => 'jwt',
    requestTimeout: null,
    renewSession: () async {
      renewals++;
      return SessionRenewal.rejected;
    },
    onUnauthorized: () async {
      signOuts++;
    },
  );

  Future<Result<bool>> board(ApiTransport transport) => transport
      .getObject<bool>('/seasons/s/leaderboard', parse: (json) => true);

  for (final String code in <String>[
    'leaderboard.not_a_participant',
    'prediction.not_a_participant',
    'group.not_a_member',
    'auth.insufficient_role',
  ]) {
    test('401 $code is returned as an error and keeps the session', () async {
      final result = await board(build(code));

      final error = (result as Err<bool>).error;
      expect(error.code, code);
      expect(error.kind, ErrorKind.authorization);
      expect(renewals, 0);
      expect(signOuts, 0);
    });
  }

  test('a refused image read keeps the session too', () async {
    final result = await build(
      'leaderboard.not_a_participant',
    ).getBytes('/champions/s/photos/u');

    expect(result, isA<Err<Object?>>());
    expect(renewals, 0);
    expect(signOuts, 0);
  });

  for (final String? code in <String?>[
    'auth.token_expired',
    'auth.account_suspended',
    null,
  ]) {
    test('401 ${code ?? 'without an envelope'} renews, and a refused '
        'renewal ends the session', () async {
      final result = await board(build(code));

      expect(result, isA<Err<bool>>());
      expect(renewals, 1);
      expect(signOuts, 1);
    });
  }
}
