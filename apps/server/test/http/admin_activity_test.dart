import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/admin_activity.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`).
// ignore: always_use_package_imports
import '../../routes/owner/admin-activity/index.dart' as route;
import '../routes/competition_route_harness.dart';

const _other = '0c0c0c0c-0c0c-4c0c-8c0c-0c0c0c0c0c0c';

final class _Log implements AdminActivityLog {
  final List<(String, String, String, int)> kept = [];

  @override
  Future<Result<void>> record({
    required UserId actor,
    required String method,
    required String path,
    required int status,
  }) async {
    kept.add((actor.value, method, path, status));
    return const Result.ok(null);
  }

  @override
  Future<Result<List<AdminActivity>>> latest({int limit = 200}) async =>
      Result.ok([
        AdminActivity(
          id: 1,
          actorName: 'Khalid',
          method: 'POST',
          path: '/admin/users/$_other/display-name',
          at: DateTime.utc(2026, 11, 21, 18),
          target: 'Sami',
        ),
      ]);
}

final class _Seats implements OwnerNotices {
  const _Seats();

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(kAdminId));

  @override
  Future<Result<bool>> isOwner(UserId user) async =>
      Result.ok(user == const UserId(kAdminId));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

AuthenticatedUser _as(String id, PlatformRole role) =>
    AuthenticatedUser(userId: UserId(id), role: role);

// NK300_12
/// Script 300: what the server keeps of an admin's change, and the owners'
/// read of it.
void main() {
  group('isAdminActivityPath', () {
    test('the admin paths are kept', () {
      expect(isAdminActivityPath('/admin/users/x/display-name'), isTrue);
      expect(isAdminActivityPath('/fixtures/x/result'), isTrue);
      expect(isAdminActivityPath('/fixtures'), isTrue);
      expect(isAdminActivityPath('/competitions/x/seasons'), isTrue);
      expect(isAdminActivityPath('/seasons/x/fixtures'), isTrue);
      expect(isAdminActivityPath('/seasons/x/fixtures/y'), isTrue);
    });

    test('an admin playing is not kept', () {
      expect(isAdminActivityPath('/seasons/x/fixtures/y/prediction'), isFalse);
      expect(
        isAdminActivityPath('/seasons/x/fixtures/y/predictions/z/reaction'),
        isFalse,
      );
      expect(isAdminActivityPath('/seasons/x/participants'), isFalse);
      expect(isAdminActivityPath('/me/device-token'), isFalse);
      expect(isAdminActivityPath('/groups/x/members'), isFalse);
      expect(
        isAdminActivityPath('/admin/support/conversations/x/read'),
        isFalse,
      );
    });
  });

  group('keepAdminActivity', () {
    late _Log log;
    setUp(() => log = _Log());

    Future<void> keep(
      PlatformRole role, {
      HttpMethod method = HttpMethod.put,
      String path = '/fixtures/f/result',
      int status = HttpStatus.ok,
    }) => keepAdminActivity(
      log: log,
      principal: _as(kAdminId, role),
      method: method,
      path: path,
      status: status,
    );

    test('an admin change answered below 400 is kept', () async {
      await keep(PlatformRole.admin);
      expect(log.kept, [(kAdminId, 'PUT', '/fixtures/f/result', 200)]);
    });

    test('a player, a read, a refusal or an own play are not', () async {
      await keep(PlatformRole.user);
      await keep(PlatformRole.admin, method: HttpMethod.get);
      await keep(PlatformRole.admin, status: HttpStatus.conflict);
      await keep(PlatformRole.admin, path: '/seasons/s/fixtures/f/prediction');
      expect(log.kept, isEmpty);
    });
  });

  group('GET /owner/admin-activity', () {
    late CompositionRoot root;
    setUp(() {
      root = CompositionRoot.forTesting(
        ownerAdminActivity: OwnerAdminActivity(
          log: _Log(),
          owners: const _Seats(),
        ),
      );
    });

    test(
      'an owner seat reads each change with the admin and the target',
      () async {
        final body = await decodeBody(
          await route.onRequest(
            wireContext(
              root: root,
              principal: adminPrincipal(),
              method: HttpMethod.get,
            ),
          ),
        );
        final line =
            (body['entries']! as List<Object?>).single!
                as Map<Object?, Object?>;
        expect(line['actor_name'], 'Khalid');
        expect(line['target'], 'Sami');
      },
    );

    test('another admin is refused', () async {
      final Response response = await route.onRequest(
        wireContext(
          root: root,
          principal: _as(_other, PlatformRole.admin),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, isNot(HttpStatus.ok));
    });
  });
}
