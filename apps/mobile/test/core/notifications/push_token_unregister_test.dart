/// Audit M-05: signing out unbinds this phone from the player's pushes,
/// through the real [PushTokenService] and `AuthApi` over the auth
/// harness's fake server.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/providers.dart';

import '../../support/auth_harness.dart';

void main() {
  test('the token is sent to be unbound while the session holds', () async {
    final List<http.Request> removals = <http.Request>[];
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/me/device-token/remove') {
        removals.add(request);
        return http.Response(
          jsonEncode(const {'schema_version': 1, 'registered': false}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return okMe(sampleUser);
    }, seedToken: 'saved-jwt');
    addTearDown(harness.dispose);

    await harness.container
        .read(pushTokenServiceProvider)
        .unregisterCurrentDevice(token: 'phone-token');

    final http.Request removal = removals.single;
    expect(removal.method, 'POST');
    expect(jsonDecode(removal.body), {'token': 'phone-token'});
    expect(removal.headers['authorization'], 'Bearer saved-jwt');
  });

  test('a refused removal never throws into the sign-out', () async {
    final harness = buildAuthHarness(
      (_) async => http.Response('nope', 503),
      seedToken: 'saved-jwt',
    );
    addTearDown(harness.dispose);

    await expectLater(
      harness.container
          .read(pushTokenServiceProvider)
          .unregisterCurrentDevice(token: 'phone-token'),
      completes,
    );
  });
}
