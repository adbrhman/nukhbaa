import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [HiddenAccountStore] over `identity.users.hidden_at`
/// (script 258, migration 0207).
///
/// Writes only that column. The boards drop a hidden account within their
/// cache's life (30 to 60 seconds): every reader that leaves out a suspended
/// account leaves out a hidden one too.
///
/// Total: never throws; a malformed row is a transient
/// `identity.row_corrupt`.
final class PostgresHiddenAccountStore implements HiddenAccountStore {
  /// Creates the store over an open [PostgresConnection].
  const PostgresHiddenAccountStore(this._connection);

  final PostgresConnection _connection;

  /// The most an owner list returns.
  static const int maxListed = 200;

  static const String _listSql = '''
SELECT u.id::text AS id, u.email, u.role::text AS role,
       u.status::text AS status, u.display_name, u.hidden_at
FROM identity.users u
WHERE u.hidden_at IS NOT NULL
ORDER BY u.hidden_at DESC, u.id
LIMIT @limit
''';

  static const String _hideSql = '''
UPDATE identity.users
SET hidden_at = coalesce(hidden_at, now()),
    updated_at = now()
WHERE id = @id
RETURNING id
''';

  static const String _showSql = '''
UPDATE identity.users
SET hidden_at = NULL,
    updated_at = now()
WHERE id = @id
RETURNING id
''';

  @override
  Future<Result<List<HiddenAccount>>> list() async {
    final result = await _connection.query(
      _listSql,
      parameters: {'limit': maxListed},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _map(value),
    };
  }

  @override
  Future<Result<bool>> hide(UserId target) => _write(_hideSql, target);

  @override
  Future<Result<bool>> show(UserId target) => _write(_showSql, target);

  Future<Result<bool>> _write(String sql, UserId target) async {
    final result = await _connection.query(
      sql,
      parameters: {'id': target.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty,
      ),
    };
  }

  static Result<List<HiddenAccount>> _map(List<Map<String, dynamic>> rows) {
    final List<HiddenAccount> out = <HiddenAccount>[];
    for (final Map<String, dynamic> row in rows) {
      final idResult = UserId.tryParse(row['id']?.toString());
      if (idResult is Err<UserId>) return Result.err(_corrupt('id'));
      final roleResult = PlatformRole.tryParse(row['role']?.toString());
      if (roleResult is Err<PlatformRole>) return Result.err(_corrupt('role'));
      final UserStatus status;
      switch (row['status']?.toString()) {
        case 'active':
          status = UserStatus.active;
        case 'suspended':
          status = UserStatus.suspended;
        default:
          return Result.err(_corrupt('status'));
      }
      final DateTime? hiddenAt = switch (row['hidden_at']) {
        final DateTime t => t.toUtc(),
        final String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      };
      if (hiddenAt == null) return Result.err(_corrupt('hidden_at'));
      out.add(
        HiddenAccount(
          user: User(
            id: (idResult as Ok<UserId>).value,
            email: row['email'] as String?,
            role: (roleResult as Ok<PlatformRole>).value,
            status: status,
            displayName: (row['display_name'] as String?) ?? '',
          ),
          hiddenAt: hiddenAt,
        ),
      );
    }
    return Result.ok(out);
  }

  static AppError _corrupt(String field) => AppError.transient(
    'identity.row_corrupt',
    'A hidden-account row has an invalid $field',
  );
}
