import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  const adminId = adminUuid;
  const targetId = targetUuid;

  test('search matches display name as well as email', () async {
    final users = InMemoryUserAdminRepository();
    users.seed(
      storedUser(
        id: targetId,
        email: 'email@example.com',
      ).copyWith(displayName: 'علي المغربي'),
    );
    final useCase = ListUsers(users: users);

    final result = await useCase(
      principal: principal(userId: adminId),
      search: 'المغربي',
    );

    expect(result, isA<Ok<List<User>>>());
    expect((result as Ok<List<User>>).value.single.displayName, 'علي المغربي');
  });
}
