import 'dart:typed_data';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [UserDirectory] over the canonical `identity.users` table.
final class PostgresUserDirectory implements UserDirectory {
  const PostgresUserDirectory(this._connection);

  final PostgresConnection _connection;

  static const String _upsertSql = '''
    INSERT INTO identity.users (id, email, role, status, display_name)
    VALUES (@id, @email, @role, 'active', @displayName)
    ON CONFLICT (id) DO UPDATE
      SET email = COALESCE(EXCLUDED.email, identity.users.email),
          updated_at = now()
    RETURNING id, email, role::text, status::text, display_name,
              avatar_mime, avatar_updated_at
  ''';

  static const String _updateDisplayNameSql = '''
    UPDATE identity.users
    SET display_name = @displayName,
        updated_at = now()
    WHERE id = @id
    RETURNING id, email, role::text, status::text, display_name,
              avatar_mime, avatar_updated_at
  ''';

  // The three avatar columns move together -- a row with bytes and no mime
  // would be unservable -- so one statement writes all three, and one clears
  // all three. The database CHECK from migration 0033 backs that up.
  static const String _setAvatarSql = '''
    UPDATE identity.users
    SET avatar_bytes = @bytes,
        avatar_mime = @mime,
        avatar_updated_at = now(),
        updated_at = now()
    WHERE id = @id
    RETURNING id, email, role::text, status::text, display_name,
              avatar_mime, avatar_updated_at
  ''';

  static const String _clearAvatarSql = '''
    UPDATE identity.users
    SET avatar_bytes = NULL,
        avatar_mime = NULL,
        avatar_updated_at = NULL,
        updated_at = now()
    WHERE id = @id
    RETURNING id, email, role::text, status::text, display_name,
              avatar_mime, avatar_updated_at
  ''';

  // The one statement in the codebase that reads image bytes.
  static const String _readAvatarSql = '''
    SELECT avatar_bytes, avatar_mime, avatar_updated_at
    FROM identity.users
    WHERE id = @id
  ''';

  static const String _findByIdSql = '''
    SELECT id, email, role::text, status::text, display_name,
           avatar_mime, avatar_updated_at
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
        'role': principal.role.name,
        'displayName': principal.displayName,
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
        displayName: (row['display_name'] as String?) ?? '',
        avatarMime: row['avatar_mime'] as String?,
        avatarUpdatedAt: row['avatar_updated_at'] as DateTime?,
      ),
    );
  }

  /// Persists a new, already-validated [displayName] for [userId]
  /// (`UpdateDisplayName` use-case). Unlike [ensureUser], this ALWAYS writes
  /// the column — it is the one path allowed to change a name after signup.
  @override
  Future<Result<User>> updateDisplayName(
    UserId userId,
    String displayName,
  ) async {
    final queryResult = await _connection.query(
      _updateDisplayNameSql,
      parameters: {'id': userId.value, 'displayName': displayName},
    );
    return switch (queryResult) {
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.err(
                AppError.transient(
                  'identity.update_no_row',
                  'Display name update affected no user row',
                ),
              )
            : _mapSingleRow(value),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
    };
  }

  @override
  Future<Result<User>> setAvatar(
    UserId userId,
    List<int> bytes,
    String mime,
  ) async {
    final queryResult = await _connection.query(
      _setAvatarSql,
      parameters: {
        'id': userId.value,
        // Uint8List, never a bare List<int>: the driver infers the Postgres
        // type from the Dart value, and a List<int> is inferred as an integer
        // ARRAY. Postgres then coerces that array's text form into bytea, so
        // the column ends up holding the ASCII of '{255,216,...}' -- four
        // characters per byte -- instead of the image. The route serves those
        // bytes with the right content type and every decoder rejects them.
        'bytes': Uint8List.fromList(bytes),
        'mime': mime,
      },
    );
    return _mapAvatarWrite(queryResult);
  }

  @override
  Future<Result<User>> clearAvatar(UserId userId) async {
    final queryResult = await _connection.query(
      _clearAvatarSql,
      parameters: {'id': userId.value},
    );
    return _mapAvatarWrite(queryResult);
  }

  @override
  Future<Result<StoredAvatar?>> readAvatar(UserId userId) async {
    final queryResult = await _connection.query(
      _readAvatarSql,
      parameters: {'id': userId.value},
    );
    return switch (queryResult) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapAvatarRead(value),
    };
  }

  Result<StoredAvatar?> _mapAvatarRead(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Result.ok(null);
    }
    final row = rows.first;
    final bytes = row['avatar_bytes'];
    final mime = row['avatar_mime'] as String?;
    final updatedAt = row['avatar_updated_at'] as DateTime?;
    // No picture is an ordinary answer, not a missing one.
    if (bytes == null || mime == null || updatedAt == null) {
      return const Result.ok(null);
    }
    if (bytes is! List<int>) {
      return Result.err(_corrupt('avatar_bytes', 'not a byte list'));
    }
    return Result.ok(
      StoredAvatar(bytes: bytes, mime: mime, updatedAt: updatedAt.toUtc()),
    );
  }

  Result<User> _mapAvatarWrite(Result<List<Map<String, dynamic>>> queryResult) {
    return switch (queryResult) {
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.err(
                AppError.transient(
                  'identity.update_no_row',
                  'Avatar update affected no user row',
                ),
              )
            : _mapSingleRow(value),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
    };
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
