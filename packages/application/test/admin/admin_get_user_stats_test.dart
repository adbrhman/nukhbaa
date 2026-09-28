import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  const adminId = adminUuid;

  test(
    'counts EVERY stored user by status, not a bounded browse page',
    () async {
      final users = InMemoryUserAdminRepository();
      users.seed(storedUser(id: 'user-1'));
      users.seed(storedUser(id: 'user-2'));
      users.seed(storedUser(id: 'user-3'));
      users.seed(storedUser(id: targetUuid, status: UserStatus.suspended));
      final useCase = AdminGetUserStats(users: users);

      final result = await useCase(principal: principal(userId: adminId));

      expect(result, isA<Ok<UserCounts>>());
      final counts = (result as Ok<UserCounts>).value;
      expect(counts.total, 4);
      expect(counts.active, 3);
      expect(counts.suspended, 1);
    },
  );

  test('a non-admin is refused, never reaching the repository', () async {
    final users = InMemoryUserAdminRepository();
    users.seed(storedUser(id: 'user-1'));
    final useCase = AdminGetUserStats(users: users);

    final result = await useCase(
      principal: principal(userId: adminId, role: PlatformRole.user),
    );

    expect(result, isA<Err<UserCounts>>());
    expect((result as Err<UserCounts>).error.code, 'auth.insufficient_role');
  });

  test('a transient repository failure propagates untouched', () async {
    final users = InMemoryUserAdminRepository();
    users.failNextWith(const AppError.transient('db.down', 'unreachable'));
    final useCase = AdminGetUserStats(users: users);

    final result = await useCase(principal: principal(userId: adminId));

    expect(result, isA<Err<UserCounts>>());
    expect((result as Err<UserCounts>).error.code, 'db.down');
  });
}
