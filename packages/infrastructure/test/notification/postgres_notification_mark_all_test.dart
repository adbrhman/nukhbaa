import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_notification_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
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

/// Hermetic tests of `markAllRead`: one recipient-scoped, `read_at IS NULL`
/// guarded update that answers how many rows it marked. The statement was
/// run by hand against migration 0009's table.
void main() {
  const recipient = UserId('22222222-2222-2222-2222-222222222222');
  final readAt = DateTime.utc(2026, 10, 6, 15);

  test('marks only the unread rows of the recipient and counts them', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'marked': 3},
      ]),
    );

    final result = await PostgresNotificationRepository(
      connection,
    ).markAllRead(recipient, readAt);

    expect((result as Ok<int>).value, 3);
    final String sql = connection.sqls.single;
    expect(sql, contains('UPDATE notification.notifications'));
    expect(sql, contains('recipient_id = @recipient_id'));
    expect(sql, contains('read_at IS NULL'));
    expect(connection.params.single, {
      'recipient_id': recipient.value,
      'read_at': readAt,
    });
  });

  test('a count the driver sends as text is still read', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'marked': '0'},
      ]),
    );

    final result = await PostgresNotificationRepository(
      connection,
    ).markAllRead(recipient, readAt);

    expect((result as Ok<int>).value, 0);
  });

  test('a driver failure is returned, not thrown', () async {
    final connection = _FakeConnection(
      const Result.err(AppError.transient('db.unavailable', 'down')),
    );

    final result = await PostgresNotificationRepository(
      connection,
    ).markAllRead(recipient, readAt);

    expect((result as Err<int>).error.code, 'db.unavailable');
  });
}
