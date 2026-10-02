import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_duplicate_name_reader.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _c = '33333333-3333-4333-8333-333333333333';
const _d = '44444444-4444-4444-8444-444444444444';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  Map<String, Object?>? lastParameters;

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    lastParameters = parameters;
    return _response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) => action(this);

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _row(
  String id,
  String name,
  String key, {
  String status = 'active',
}) => {
  'id': id,
  'email': '$id@t.io',
  'role': 'user',
  'status': status,
  'display_name': name,
  'name_key': key,
};

void main() {
  test('consecutive rows with one key form one group, in order', () async {
    final connection = _FakeConnection(
      Result.ok([
        _row(_a, 'أحمد', 'احمد'),
        _row(_b, 'احمد', 'احمد'),
        _row(_c, 'خالد', 'خالد'),
        _row(_d, 'خالد', 'خالد', status: 'suspended'),
      ]),
    );

    final result = await PostgresDuplicateNameReader(
      connection,
    ).duplicateNames(limit: 7);

    final groups = (result as Ok<List<DuplicateNameGroup>>).value;
    expect(groups, hasLength(2));
    expect(groups[0].users.map((u) => u.id.value), [_a, _b]);
    expect(groups[1].users.map((u) => u.displayName), ['خالد', 'خالد']);
    expect(groups[1].users[1].status, UserStatus.suspended);
    expect(connection.lastParameters, {'limit': 7});
  });

  test('no rows is no groups', () async {
    final result = await PostgresDuplicateNameReader(
      _FakeConnection(const Result.ok([])),
    ).duplicateNames(limit: 5);

    expect((result as Ok<List<DuplicateNameGroup>>).value, isEmpty);
  });

  test('a row with an unknown status is transient, not a guess', () async {
    final result = await PostgresDuplicateNameReader(
      _FakeConnection(Result.ok([_row(_a, 'x', 'x', status: 'deleted')])),
    ).duplicateNames(limit: 5);

    expect(
      (result as Err<List<DuplicateNameGroup>>).error.code,
      'identity.row_corrupt',
    );
  });
}
