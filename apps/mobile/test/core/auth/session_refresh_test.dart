import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/auth/session_refresher.dart';
import 'package:mobile/core/auth/token_store.dart';
import 'package:mobile/features/auth/session_controller.dart';
import 'package:shared/shared.dart';

import '../../support/auth_harness.dart';

const Map<String, String> _jsonHeaders = {'content-type': 'application/json'};

void main() {
  late InMemoryTokenStore store;
  late int refreshCalls;
  late int ended;

  setUp(() async {
    store = InMemoryTokenStore('stale');
    await store.writeRefreshToken('r1');
    refreshCalls = 0;
    ended = 0;
  });

  /// The production transport wiring over a fake server whose `/auth/refresh`
  /// answers with [refreshResponse] and whose other routes accept only the
  /// renewed token.
  Future<Result<bool>> callMe(
    http.Response Function() refreshResponse, {
    int parallel = 1,
  }) async {
    final transport = buildSessionTransport(
      baseUri: Uri.parse('https://api.test.example/'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls++;
          expect(jsonDecode(request.body), {'refresh_token': 'r1'});
          return refreshResponse();
        }
        return request.headers['authorization'] == 'Bearer fresh'
            ? http.Response(jsonEncode({'ok': true}), 200)
            : http.Response('', 401);
      }),
      store: store,
      onSessionEnded: () async {
        ended++;
        await store.clear();
      },
      requestTimeout: null,
    );
    final results = await Future.wait([
      for (var i = 0; i < parallel; i++)
        transport.getObject<bool>('/me', parse: (json) => json['ok']! as bool),
    ]);
    return results.first;
  }

  http.Response renewed() => http.Response(
    jsonEncode(
      const AuthResponseDto(
        accessToken: 'fresh',
        refreshToken: 'r2',
        userId: null,
        email: null,
      ).toJson(),
    ),
    200,
    headers: _jsonHeaders,
  );

  test('an expired access token is renewed silently and the rotated '
      'refresh token is kept', () async {
    final result = await callMe(renewed);

    expect(result, isA<Ok<bool>>());
    expect(refreshCalls, 1);
    expect(ended, 0);
    expect(await store.read(), 'fresh');
    expect(await store.readRefreshToken(), 'r2');
  });

  test('parallel 401s share a single renewal', () async {
    final result = await callMe(renewed, parallel: 3);

    expect(result, isA<Ok<bool>>());
    expect(refreshCalls, 1);
  });

  test('a refused renewal ends the session and forgets both tokens', () async {
    final result = await callMe(
      () => http.Response(
        jsonEncode({
          'schema_version': 1,
          'code': 'auth.rejected',
          'message': 'Invalid Refresh Token',
        }),
        400,
        headers: _jsonHeaders,
      ),
    );

    expect(result, isA<Err<bool>>());
    expect(ended, 1);
    expect(await store.read(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('signing in keeps the refresh token for later renewals', () async {
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/auth/login') {
        return http.Response(
          jsonEncode({
            'schema_version': 1,
            'access_token': 'a1',
            'refresh_token': 'r9',
          }),
          200,
          headers: _jsonHeaders,
        );
      }
      return okMe(sampleUser);
    });
    addTearDown(harness.dispose);
    await harness.container.read(sessionControllerProvider.future);

    await harness.container
        .read(sessionControllerProvider.notifier)
        .signInWithCredentials(email: 'a@example.com', password: 'secret-123');

    expect(await harness.store.read(), 'a1');
    expect(await harness.store.readRefreshToken(), 'r9');
  });
}
