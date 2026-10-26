import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/group/postgres_invitee_directory.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// Hermetic tests for the league-invitee search adapter: the bindings and
// the row mapping (the SQL itself runs against Postgres in production).

const _recipientId = '33333333-3333-4333-8333-333333333333';
const _callerId = '44444444-4444-4444-8444-444444444444';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
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

_FakeConnection _rows(List<Map<String, dynamic>> rows) =>
    _FakeConnection(Result.ok(rows));

void main() {
  group('PostgresInviteeDirectory', () {
    test('binds the query, the caller and the limit', () async {
      final conn = _rows([
        {'user_id': _recipientId, 'display_name': 'Badr'},
      ]);

      final result = await PostgresInviteeDirectory(
        conn,
      ).search(query: 'Bad', excluding: const UserId(_callerId), limit: 20);

      final player = (result as Ok<List<GroupInvitee>>).value.single;
      expect(player.userId, const UserId(_recipientId));
      expect(player.displayName, 'Badr');
      expect(conn.parameters.single, {
        'query': 'Bad',
        'excluding': _callerId,
        'limit': 20,
      });
      expect(conn.sqls.single, contains("u.status = 'active'"));
    });

    test('a row without a name is row_corrupt', () async {
      final result = await PostgresInviteeDirectory(
        _rows([
          {'user_id': _recipientId, 'display_name': null},
        ]),
      ).search(query: 'Bad', excluding: const UserId(_callerId), limit: 20);

      expect(
        (result as Err<List<GroupInvitee>>).error.code,
        'group.row_corrupt',
      );
    });
  });
}
