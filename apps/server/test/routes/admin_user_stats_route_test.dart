import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/user-stats/index.dart' as route;
import 'competition_route_harness.dart';

Future<Response> _call(
  InMemoryUserAdminRepository users,
  AuthenticatedUser principal, {
  HttpMethod method = HttpMethod.get,
}) => route.onRequest(
  wireContext(
    root: CompositionRoot.forTesting(
      adminGetUserStats: AdminGetUserStats(users: users),
    ),
    principal: principal,
    method: method,
  ),
);

void main() {
  group('GET /admin/user-stats', () {
    test('an admin reads the TRUE total, not a bounded page', () async {
      final users = InMemoryUserAdminRepository();
      // More rows than ListUsers.maxLimit (50) — proves this endpoint is a
      // real aggregate, never a page length.
      for (var i = 0; i < 60; i++) {
        users.seed(
          storedUser(
            id: 'aaaaaaaa-0000-4000-8000-${i.toString().padLeft(12, '0')}',
          ),
        );
      }
      users.seed(storedUser(id: kTargetUserId, status: UserStatus.suspended));

      final response = await _call(users, adminPrincipal());

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['total'], 61);
      expect(body['active'], 60);
      expect(body['suspended'], 1);
    });

    test('a player is refused', () async {
      final response = await _call(
        InMemoryUserAdminRepository(),
        userPrincipal(),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('any other method is 405', () async {
      final response = await _call(
        InMemoryUserAdminRepository(),
        adminPrincipal(),
        method: HttpMethod.post,
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
