import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/device-token/remove.dart' as route;
import 'competition_route_harness.dart';

/// In-memory stand-in for `notification.device_tokens`.
final class _Tokens implements DeviceTokenRepository {
  final Map<String, String> owners = <String, String>{};

  @override
  Future<Result<void>> upsert({
    required UserId userId,
    required String token,
    required String platform,
  }) async {
    owners[token] = userId.value;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> remove({
    required UserId userId,
    required String token,
  }) async {
    if (owners[token] == userId.value) owners.remove(token);
    return const Result.ok(null);
  }
}

// Audit M-05: signing out unbinds the phone from the player's pushes.
void main() {
  late _Tokens tokens;
  late CompositionRoot root;

  setUp(() {
    tokens = _Tokens();
    root = CompositionRoot.forTesting(
      registerDeviceToken: RegisterDeviceToken(deviceTokens: tokens),
    );
  });

  test('the token of the caller is removed', () async {
    tokens.owners['phone-1'] = kUserId;

    final response = await route.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        body: const {'token': 'phone-1'},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect((await decodeBody(response))['registered'], isFalse);
    expect(tokens.owners, isEmpty);
  });

  test('a token since bound to another player is left alone', () async {
    tokens.owners['phone-1'] = '99999999-9999-4999-8999-999999999999';

    final response = await route.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        body: const {'token': 'phone-1'},
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(tokens.owners, hasLength(1));
  });

  test('only POST is allowed', () async {
    final response = await route.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
