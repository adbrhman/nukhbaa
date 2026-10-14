import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/group/postgres_group_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _groupId = '11111111-1111-4111-8111-111111111111';
const _userId = '22222222-2222-4222-8222-222222222222';
const _seasonId = '33333333-3333-4333-8333-333333333333';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  String? lastSql;
  Map<String, Object?>? lastParameters;

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    lastSql = sql;
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

void main() {
  group('removeMembership', () {
    test('a removed member is true; the owner row is never touched', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'removed': 1},
        ]),
      );

      final result = await PostgresGroupRepository(
        connection,
      ).removeMembership(const GroupId(_groupId), const UserId(_userId));

      expect((result as Ok<bool>).value, isTrue);
      expect(connection.lastParameters, {
        'group_id': _groupId,
        'user_id': _userId,
      });
      expect(connection.lastSql, contains("role = 'member'"));
      // The invitation that brought him in goes too.
      expect(connection.lastSql, contains('"group".group_invitations'));
    });

    test('no such member is false', () async {
      final result = await PostgresGroupRepository(
        _FakeConnection(
          const Result.ok([
            {'removed': 0},
          ]),
        ),
      ).removeMembership(const GroupId(_groupId), const UserId(_userId));

      expect((result as Ok<bool>).value, isFalse);
    });
  });

  group('deleteGroup', () {
    test('a deleted league is true', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'deleted': 1},
        ]),
      );

      final result = await PostgresGroupRepository(
        connection,
      ).deleteGroup(const GroupId(_groupId));

      expect((result as Ok<bool>).value, isTrue);
      expect(connection.lastParameters, {'group_id': _groupId});
    });

    test('a failure passes through', () async {
      const failure = AppError.transient('db.query_timeout', 'timed out');

      final result = await PostgresGroupRepository(
        _FakeConnection(const Result.err(failure)),
      ).deleteGroup(const GroupId(_groupId));

      expect((result as Err<bool>).error, failure);
    });
  });

  test('memberParticipantIds reads the whole roster at once', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'participant_id': 'p-1'},
        {'participant_id': 'p-2'},
      ]),
    );

    final result = await PostgresGroupRepository(
      connection,
    ).memberParticipantIds(const GroupId(_groupId), const SeasonId(_seasonId));

    expect((result as Ok<Set<String>>).value, {'p-1', 'p-2'});
    expect(connection.lastParameters, {
      'group_id': _groupId,
      'season_id': _seasonId,
    });
  });
}
