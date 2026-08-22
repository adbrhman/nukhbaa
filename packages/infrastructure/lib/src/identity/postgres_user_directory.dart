import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [UserDirectory] over the canonical `identity.users` table.
final class PostgresUserDirectory implements UserDirectory {
  const PostgresUserDirectory(this._connection);

  final PostgresConnection _connection;

  static const String _upsertSql = '''
    INSERT INTO identity.users (id, email, role, status)
    VALUES (@id, @email, 'user', 'active')
    ON CONFLICT (id) DO UPDATE
      SET email = EXCLUDED.email,
          updated_at = now()
    RETURNING id, email, role::text, status::text
  ''';

  static const String _findByIdSql = '''
    SELECT id, email, role::text, status::text
    FROM identity.users
    WHERE id = @id
  ''';

  @override
  Future<Result<User>> ensureUser(AuthenticatedUser principal) async {
    final queryResult = await _connection.query(
      _upsertSql,
      parameters: {
        'id': principal.userId.value,
        'email': principal.email,
        // NOTE: role is deliberately NOT a parameter. A new row is always
        // seeded as 'user'; admin and service are granted only by a platform
        // operation on the row itself (Security ADR §2).
      },
    );

    return switch (queryResult) {
      Ok<List<Map<String, dynamic>>>(:final value) => _mapSingleRow(value),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
    };
  }

  @override
  Future<Result<User?>> findUser(UserId id) async {
    final queryResult = await _connection.query(
      _findByIdSql,
      parameters: {'id': id.value},
    );

    return switch (queryResult) {
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.ok(null)
            : switch (_mapSingleRow(value)) {
                Ok<User>(:final value) => Result.ok(value),
                Err<User>(:final error) => Result.err(error),
              },
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
    };
  }

  Result<User> _mapSingleRow(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Result.err(
        AppError.transient(
          'identity.upsert_no_row',
          'User upsert returned no row',
        ),
      );
    }
    final row = rows.first;

    final idResult = UserId.tryParse(row['id']?.toString());
    final roleResult = PlatformRole.tryParse(row['role']?.toString());
    final status = _statusFrom(row['status']?.toString());

    if (idResult is Err<UserId>) {
      return Result.err(_corrupt('id', idResult.error.message));
    }
    if (roleResult is Err<PlatformRole>) {
      return Result.err(_corrupt('role', roleResult.error.message));
    }
    if (status == null) {
      return Result.err(_corrupt('status', 'unknown status value'));
    }

    return Result.ok(
      User(
        id: (idResult as Ok<UserId>).value,
        email: row['email'] as String?,
        role: (roleResult as Ok<PlatformRole>).value,
        status: status,
      ),
    );
  }

  static UserStatus? _statusFrom(String? raw) => switch (raw) {
    'active' => UserStatus.active,
    'suspended' => UserStatus.suspended,
    _ => null,
  };

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'identity.row_corrupt',
    'Stored user has invalid $field: $detail',
  );
}
