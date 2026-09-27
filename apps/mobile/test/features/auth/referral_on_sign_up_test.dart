/// A code typed at registration, or on the name screen of a first Google
/// sign-in, is claimed right after the account exists -- through the real
/// `SessionController` and `AuthApi` over the auth harness's fake server.
/// No code, no claim.
library;

import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/core/auth/install_id.dart';
import 'package:mobile/features/auth/session_controller.dart';
import 'package:mobile/features/auth/session_state.dart';
import 'package:shared/shared.dart';

import '../../support/auth_harness.dart';

final class _Server {
  final List<http.Request> requests = <http.Request>[];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    if (request.url.path == '/auth/register') {
      return okLoginResponse('new-jwt');
    }
    if (request.url.path == '/me/referral/claim') {
      return http.Response(
        jsonEncode(const {'schema_version': 1, 'status': 'claimed'}),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return okMe(sampleUser);
  }

  List<http.Request> get claims => [
    for (final r in requests)
      if (r.url.path == '/me/referral/claim') r,
  ];
}

ProviderContainer _container(_Server server) {
  final harness = buildAuthHarness(server.handle);
  addTearDown(harness.dispose);
  final container = ProviderContainer(
    overrides: [
      ...harness.overrides,
      installIdStoreProvider.overrideWithValue(
        const FixedInstallIdStore('inst-12345678'),
      ),
    ],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('registration with a code claims it once the account exists', () async {
    final server = _Server();
    final container = _container(server);
    await container.read(sessionControllerProvider.future);

    await container
        .read(sessionControllerProvider.notifier)
        .register(
          displayName: 'Khaled',
          email: 'k@example.com',
          password: 'secret-123',
          referralCode: ' ABCDEFGH ',
        );

    expect(
      container.read(sessionControllerProvider).value,
      isA<SessionAuthenticated>(),
    );
    final claim = server.claims.single;
    final body = jsonDecode(claim.body) as Map<String, Object?>;
    expect(body['code'], 'ABCDEFGH');
    expect(body['install_id'], 'inst-12345678');
    // The claim follows the registration, never precedes it.
    expect(
      server.requests.indexWhere((r) => r.url.path == '/auth/register'),
      lessThan(server.requests.indexOf(claim)),
    );
  });

  test('registration without a code claims nothing', () async {
    final server = _Server();
    final container = _container(server);
    await container.read(sessionControllerProvider.future);

    await container
        .read(sessionControllerProvider.notifier)
        .register(
          displayName: 'Khaled',
          email: 'k@example.com',
          password: 'secret-123',
        );

    expect(server.claims, isEmpty);
  });

  test('the name screen of a first Google sign-in claims its code', () async {
    final server = _Server();
    final container = _container(server);
    await container.read(sessionControllerProvider.future);

    final result = await container
        .read(sessionControllerProvider.notifier)
        .chooseDisplayName(displayName: 'Omar', referralCode: 'QWERTYUP');

    expect(result, isA<Ok<void>>());
    final body = jsonDecode(server.claims.single.body) as Map<String, Object?>;
    expect(body['code'], 'QWERTYUP');
  });

  test('a failed claim never fails the sign-up', () async {
    int claimCalls = 0;
    final harness = buildAuthHarness((request) async {
      if (request.url.path == '/auth/register') {
        return okLoginResponse('new-jwt');
      }
      if (request.url.path == '/me/referral/claim') {
        claimCalls++;
        return errorEnvelope(503, 'db.query_failed', 'down');
      }
      return okMe(
        const AuthenticatedUserDto(
          userId: 'u-2',
          role: 'user',
          status: 'active',
          email: 'x@example.com',
        ),
      );
    });
    addTearDown(harness.dispose);
    final container = ProviderContainer(
      overrides: [
        ...harness.overrides,
        installIdStoreProvider.overrideWithValue(
          const FixedInstallIdStore(null),
        ),
      ],
      retry: (retryCount, error) => null,
    );
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.future);

    await container
        .read(sessionControllerProvider.notifier)
        .register(
          displayName: 'X',
          email: 'x@example.com',
          password: 'secret-123',
          referralCode: 'ABCDEFGH',
        );

    expect(
      container.read(sessionControllerProvider).value,
      isA<SessionAuthenticated>(),
    );
    expect(claimCalls, 1);
  });
}
