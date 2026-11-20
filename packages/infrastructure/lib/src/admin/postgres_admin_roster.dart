import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [AdminRoster] over `identity.users`,
/// `admin.role_changes` and `admin.end_user_sessions` (script 294,
/// migration 0223).
///
/// Total: never throws; a malformed row is a transient `admin.row_corrupt`.
// NK294_03
final class PostgresAdminRoster implements AdminRoster {
  /// Creates the roster over an open [PostgresConnection].
  const PostgresAdminRoster(this._connection);

  final PostgresConnection _connection;

  static const String _adminsSql = '''
SELECT id::text AS id, coalesce(display_name, '') AS display_name, email,
       status::text AS status
FROM identity.users
WHERE role = 'admin' AND deleted_at IS NULL
ORDER BY display_name, id
''';

  static const String _promoteSql = '''
UPDATE identity.users
SET role = 'admin', updated_at = now()
WHERE id = @id::uuid AND role = 'user' AND deleted_at IS NULL
RETURNING id
''';

  static const String _revokeSql = '''
UPDATE identity.users
SET role = 'user', updated_at = now()
WHERE id = @id::uuid AND role = 'admin' AND deleted_at IS NULL
RETURNING id
''';

  static const String _endSql = '''
SELECT admin.end_user_sessions(@id::uuid) AS ended
''';

  static const String _recordSql = '''
INSERT INTO admin.role_changes
  (user_id, action, reason, changed_by, sessions_ended)
VALUES (@user::uuid, @action, @reason, @by::uuid, @ended::int)
''';

  static const String _changesSql = '''
SELECT coalesce(u.display_name, '') AS user_name,
       c.action,
       c.reason,
       b.display_name AS by_name,
       c.occurred_at,
       c.sessions_ended
FROM admin.role_changes c
JOIN identity.users u ON u.id = c.user_id
LEFT JOIN identity.users b ON b.id = c.changed_by
ORDER BY c.occurred_at DESC, c.id DESC
LIMIT @limit
''';

  @override
  Future<Result<List<AdminMember>>> admins() async {
    final result = await _connection.query(_adminsSql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<AdminMember> out = <AdminMember>[];
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Result<UserId> id = UserId.tryParse(row['id']?.toString());
      final Object? name = row['display_name'];
      final Object? email = row['email'];
      if (id is! Ok<UserId> || name is! String) {
        return const Result.err(_corrupt);
      }
      out.add(
        AdminMember(
          id: id.value,
          displayName: name,
          email: email is String ? email : null,
          active: row['status']?.toString() == 'active',
        ),
      );
    }
    return Result.ok(out);
  }

  @override
  Future<Result<bool>> setRole({
    required UserId user,
    required bool admin,
  }) async {
    final result = await _connection.query(
      admin ? _promoteSql : _revokeSql,
      parameters: {'id': user.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  @override
  Future<Result<int>> endSessions(UserId user) async {
    final result = await _connection.query(
      _endSql,
      parameters: {'id': user.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<Map<String, dynamic>> rows =
        (result as Ok<List<Map<String, dynamic>>>).value;
    final Object? ended = rows.isEmpty ? null : rows.first['ended'];
    return ended is int ? Result.ok(ended) : const Result.err(_corrupt);
  }

  @override
  Future<Result<void>> record({
    required UserId user,
    required String action,
    required String reason,
    required UserId by,
    int? sessionsEnded,
  }) async {
    final result = await _connection.query(
      _recordSql,
      parameters: {
        'user': user.value,
        'action': action,
        'reason': reason,
        'by': by.value,
        'ended': sessionsEnded,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<List<RoleChange>>> changes({int limit = 30}) async {
    final result = await _connection.query(
      _changesSql,
      parameters: {'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<RoleChange> out = <RoleChange>[];
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? name = row['user_name'];
      final Object? action = row['action'];
      final Object? reason = row['reason'];
      final Object? by = row['by_name'];
      final Object? ended = row['sessions_ended'];
      final DateTime? at = switch (row['occurred_at']) {
        final DateTime t => t.toUtc(),
        final String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      };
      if (name is! String ||
          action is! String ||
          reason is! String ||
          at == null) {
        return const Result.err(_corrupt);
      }
      out.add(
        RoleChange(
          userName: name,
          action: action,
          reason: reason,
          byName: by is String ? by : null,
          at: at,
          sessionsEnded: ended is int ? ended : null,
        ),
      );
    }
    return Result.ok(out);
  }

  static const AppError _corrupt = AppError.transient(
    'admin.row_corrupt',
    'An admin roster row is invalid',
  );
}
