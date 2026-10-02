import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'fakes.dart';

final class _Reader implements DuplicateNameReader {
  _Reader(this.groups);

  final List<DuplicateNameGroup> groups;
  int? lastLimit;

  @override
  Future<Result<List<DuplicateNameGroup>>> duplicateNames({
    required int limit,
  }) async {
    lastLimit = limit;
    return Result.ok(groups);
  }
}

void main() {
  final pair = DuplicateNameGroup([
    storedUser(id: targetUuid),
    storedUser(id: participantUuid),
  ]);

  test('an admin reads the groups, bounded', () async {
    final reader = _Reader([pair]);

    final result = await AdminListDuplicateNames(names: reader)(
      principal: principal(userId: adminUuid),
    );

    expect(
      (result as Ok<List<DuplicateNameGroup>>).value.single.users,
      hasLength(2),
    );
    expect(reader.lastLimit, AdminListDuplicateNames.maxGroups);
  });

  test('a player is refused without a read', () async {
    final reader = _Reader([pair]);

    final result = await AdminListDuplicateNames(names: reader)(
      principal: principal(userId: adminUuid, role: PlatformRole.user),
    );

    expect(
      (result as Err<List<DuplicateNameGroup>>).error.code,
      'auth.insufficient_role',
    );
    expect(reader.lastLimit, isNull);
  });
}
