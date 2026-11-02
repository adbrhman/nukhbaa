import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/shared-devices/index.dart' as route;
import 'competition_route_harness.dart';

final class _Reader implements DeviceSightings {
  _Reader(this.groups);

  final List<SharedDeviceGroup> groups;
  int reads = 0;

  @override
  Future<Result<void>> record({
    required String installId,
    required UserId userId,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<SharedDeviceGroup>>> sharedDevices({
    required int limit,
  }) async {
    reads++;
    return Result.ok(groups);
  }
}

/// Script 200: `GET /admin/shared-devices` through the real wiring.
void main() {
  Future<Response> list(
    AuthenticatedUser principal, {
    _Reader? reader,
    HttpMethod method = HttpMethod.get,
    bool wired = true,
  }) => route.onRequest(
    wireContext(
      root: CompositionRoot.forTesting(
        adminListSharedDevices: wired
            ? AdminListSharedDevices(devices: reader ?? _Reader(const []))
            : null,
      ),
      principal: principal,
      method: method,
    ),
  );

  test(
    'an admin reads every phone with its accounts and their count',
    () async {
      final reader = _Reader([
        SharedDeviceGroup(
          users: [
            storedUser(),
            storedUser(id: kUserId, status: UserStatus.suspended),
          ],
          lastSeen: DateTime.utc(2026, 11, 2, 9),
        ),
      ]);

      final response = await list(adminPrincipal(), reader: reader);

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      final devices = body['devices']! as List<Object?>;
      final phone = (devices.single! as Map).cast<String, Object?>();
      final users = phone['users']! as List<Object?>;
      expect(users, hasLength(2));
      expect((users[1]! as Map)['status'], 'suspended');
      expect(phone['last_seen'], '2026-11-02T09:00:00.000Z');
    },
  );

  test('no shared phone is an empty list', () async {
    final response = await list(adminPrincipal());

    expect(response.statusCode, HttpStatus.ok);
    expect((await decodeBody(response))['devices'], isEmpty);
  });

  test('a player is refused and nothing is read', () async {
    final reader = _Reader(const []);

    final response = await list(userPrincipal(), reader: reader);

    expect(response.statusCode, HttpStatus.unauthorized);
    expect(reader.reads, 0);
  });

  test('an unwired root is 503', () async {
    final response = await list(adminPrincipal(), wired: false);

    expect(response.statusCode, HttpStatus.serviceUnavailable);
  });

  test('any other method is 405', () async {
    final response = await list(adminPrincipal(), method: HttpMethod.post);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
