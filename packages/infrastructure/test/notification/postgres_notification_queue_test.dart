import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_notification_queue.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _p1 = '11111111-1111-1111-1111-111111111111';
const _p2 = '22222222-2222-2222-2222-222222222222';
const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _userB = 'bbbbbbbb-0000-0000-0000-000000000002';

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
  ) async => action(this);

  @override
  Future<void> close() async {}
}

Map<String, dynamic> _row(String id, String user, String? token) => {
  'id': id,
  'user_id': user,
  'title': 'title $id',
  'body': 'body $id',
  'token': token,
};

/// Hermetic unit tests for [PostgresNotificationQueue]: a fake
/// [PostgresConnection] replays scripted rows and records the SQL and its
/// parameters. That the claim really is exclusive under two sweeps is a
/// property of FOR UPDATE SKIP LOCKED, checked by hand on the live database.
void main() {
  group('enqueue', () {
    UserId user(String raw) => (UserId.tryParse(raw) as Ok<UserId>).value;
    final at = DateTime.utc(2026, 9, 24, 5);

    PushToQueue push(String id, String userId, String title) => PushToQueue(
      id: id,
      userId: user(userId),
      title: title,
      body: 'body $title',
      deliverAfter: at,
    );

    test('inserts one row per push, keyed on its id', () async {
      final connection = _FakeConnection(const Result.ok([]));

      final result = await PostgresNotificationQueue(connection).enqueue([
        push(_p1, _userA, 't'),
        push(_p2, _userB, 't2'),
      ]);

      expect(result, isA<Ok<void>>());
      expect(connection.sqls, hasLength(2));
      expect(connection.sqls.first, contains('ON CONFLICT (id) DO NOTHING'));
      expect(connection.parameters.first, {
        'id': _p1,
        'user_id': _userA,
        'title': 't',
        'body': 'body t',
        'deliver_after': at,
      });
      expect(connection.parameters.last['user_id'], _userB);
    });

    test('nothing to queue runs no statement', () async {
      final connection = _FakeConnection(const Result.ok([]));

      final result = await PostgresNotificationQueue(connection).enqueue([]);

      expect(result, isA<Ok<void>>());
      expect(connection.sqls, isEmpty);
    });

    test('a driver failure stops at the first push', () async {
      final connection = _FakeConnection(
        const Result.err(AppError.transient('db.down', 'down')),
      );

      final result = await PostgresNotificationQueue(connection).enqueue([
        push(_p1, _userA, 't'),
        push(_p2, _userB, 't2'),
      ]);

      expect((result as Err<void>).error.code, 'db.down');
      expect(connection.sqls, hasLength(1));
    });
  });

  group('claimDue', () {
    test('claims in one statement and groups tokens per push', () async {
      final now = DateTime.utc(2026, 9, 24, 5);
      final connection = _FakeConnection(
        Result.ok([
          _row(_p1, _userA, 't1'),
          _row(_p1, _userA, 't2'),
          _row(_p2, _userB, null),
        ]),
      );

      final result = await PostgresNotificationQueue(
        connection,
      ).claimDue(now: now, limit: 50);

      final pushes = (result as Ok<List<QueuedPush>>).value;
      expect(pushes, hasLength(2));
      expect(pushes[0].id, _p1);
      expect(pushes[0].userId.value, _userA);
      expect(pushes[0].title, 'title $_p1');
      expect(pushes[0].tokens, ['t1', 't2']);
      expect(pushes[1].id, _p2);
      expect(pushes[1].tokens, isEmpty);

      expect(connection.sqls, hasLength(1));
      expect(connection.sqls.single, contains('SET sent_at = @now'));
      expect(connection.sqls.single, contains('FOR UPDATE SKIP LOCKED'));
      expect(connection.parameters.single, {'now': now, 'limit': 50});
    });

    test('nothing due answers an empty list', () async {
      final result = await PostgresNotificationQueue(
        _FakeConnection(const Result.ok([])),
      ).claimDue(now: DateTime.utc(2026, 9, 24, 5), limit: 50);

      expect((result as Ok<List<QueuedPush>>).value, isEmpty);
    });

    test('a row of the wrong shape is transient, not a guess', () async {
      final result = await PostgresNotificationQueue(
        _FakeConnection(
          Result.ok([
            {'id': _p1, 'user_id': _userA, 'title': 1, 'body': 'b'},
          ]),
        ),
      ).claimDue(now: DateTime.utc(2026, 9, 24, 5), limit: 50);

      expect((result as Err<List<QueuedPush>>).error.kind, ErrorKind.transient);
    });

    test('a driver failure is passed through', () async {
      final result = await PostgresNotificationQueue(
        _FakeConnection(
          const Result.err(AppError.transient('db.down', 'down')),
        ),
      ).claimDue(now: DateTime.utc(2026, 9, 24, 5), limit: 50);

      expect((result as Err<List<QueuedPush>>).error.code, 'db.down');
    });
  });
}
