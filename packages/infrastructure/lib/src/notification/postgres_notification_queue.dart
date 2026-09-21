import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [NotificationQueue] (migration 0064).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter, and speaks only in domain types.
final class PostgresNotificationQueue implements NotificationQueue {
  /// Creates the queue over an open [PostgresConnection].
  const PostgresNotificationQueue(this._connection);

  final PostgresConnection _connection;

  // One statement claims and reads: the UPDATE sets sent_at on the oldest
  // waiting rows that are due, skipping any row another sweep holds, and the
  // outer SELECT joins the users' devices as they are now. One row per
  // (push, token); a push whose user has no device comes back once with a
  // NULL token.
  static const String _claimSql = '''
WITH claimed AS (
  UPDATE notification.notification_queue q
  SET sent_at = @now
  WHERE q.id IN (
    SELECT w.id
    FROM notification.notification_queue w
    WHERE w.sent_at IS NULL
      AND w.deliver_after <= @now
    ORDER BY w.deliver_after, w.id
    LIMIT @limit
    FOR UPDATE SKIP LOCKED
  )
  RETURNING q.id, q.user_id, q.title, q.body, q.deliver_after
)
SELECT
  c.id::text      AS id,
  c.user_id::text AS user_id,
  c.title         AS title,
  c.body          AS body,
  dt.token        AS token
FROM claimed c
LEFT JOIN notification.device_tokens dt ON dt.user_id = c.user_id
ORDER BY c.deliver_after, c.id, dt.token
''';

  @override
  Future<Result<List<QueuedPush>>> claimDue({
    required DateTime now,
    required int limit,
  }) async {
    final result = await _connection.query(
      _claimSql,
      parameters: {'now': now.toUtc(), 'limit': limit},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _pushes(value),
    };
  }

  static const AppError _corrupt = AppError.transient(
    'notification_queue.row_corrupt',
    'a claimed queue row had unexpected column types',
  );

  // Rows arrive ordered by push, so one pass groups the tokens.
  static Result<List<QueuedPush>> _pushes(List<Map<String, dynamic>> rows) {
    final order = <String>[];
    final heads = <String, ({String userId, String title, String body})>{};
    final tokens = <String, List<String>>{};
    for (final row in rows) {
      final id = row['id'];
      final userId = row['user_id'];
      final title = row['title'];
      final body = row['body'];
      final token = row['token'];
      if (id is! String ||
          userId is! String ||
          title is! String ||
          body is! String ||
          (token != null && token is! String)) {
        return const Result.err(_corrupt);
      }
      if (!heads.containsKey(id)) {
        order.add(id);
        heads[id] = (userId: userId, title: title, body: body);
        tokens[id] = <String>[];
      }
      if (token is String) {
        tokens[id]!.add(token);
      }
    }

    final pushes = <QueuedPush>[];
    for (final id in order) {
      final head = heads[id]!;
      final parsed = UserId.tryParse(head.userId);
      if (parsed is Err<UserId>) {
        return Result.err(parsed.error);
      }
      pushes.add(
        QueuedPush(
          id: id,
          userId: (parsed as Ok<UserId>).value,
          title: head.title,
          body: head.body,
          tokens: List<String>.unmodifiable(tokens[id]!),
        ),
      );
    }
    return Result.ok(pushes);
  }
}
