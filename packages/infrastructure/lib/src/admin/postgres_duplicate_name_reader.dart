import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [DuplicateNameReader] over `identity.users`.
///
/// Names are compared by `identity.display_name_key` -- the very key the
/// 0084 trigger keeps unique -- so what this read calls a duplicate is exactly
/// what the database would refuse today. Automatic names
/// (`identity.automatic_display_name`) are left out. Suspended accounts are
/// listed too, with their status: they still hold the name.
///
/// Total: never throws; a malformed row is a transient `identity.row_corrupt`.
final class PostgresDuplicateNameReader implements DuplicateNameReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresDuplicateNameReader(this._connection);

  final PostgresConnection _connection;

  static const String _duplicatesSql = '''
WITH keyed AS (
  SELECT u.id,
         u.email,
         u.role::text AS role,
         u.status::text AS status,
         u.display_name,
         u.created_at,
         identity.display_name_key(u.display_name) AS name_key
  FROM identity.users u
  WHERE u.display_name IS NOT NULL
    AND u.display_name <> identity.automatic_display_name(u.email)
),
groups AS (
  SELECT name_key,
         count(*) AS members,
         min(created_at) AS first_at
  FROM keyed
  WHERE name_key IS NOT NULL
  GROUP BY name_key
  HAVING count(*) > 1
  ORDER BY count(*) DESC, min(created_at) ASC, name_key
  LIMIT @limit
)
SELECT k.id::text AS id,
       k.email,
       k.role,
       k.status,
       k.display_name,
       k.name_key
FROM groups g
JOIN keyed k
  ON k.name_key = g.name_key
ORDER BY g.members DESC, g.first_at ASC, g.name_key, k.created_at ASC, k.id
''';

  @override
  Future<Result<List<DuplicateNameGroup>>> duplicateNames({
    required int limit,
  }) async {
    final result = await _connection.query(
      _duplicatesSql,
      parameters: {'limit': limit},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _group(value),
    };
  }

  // Rows arrive ordered by group, so consecutive rows with one key are one
  // group.
  static Result<List<DuplicateNameGroup>> _group(
    List<Map<String, dynamic>> rows,
  ) {
    final groups = <DuplicateNameGroup>[];
    var current = <User>[];
    Object? currentKey;
    for (final row in rows) {
      final mapped = _mapUser(row);
      if (mapped is Err<User>) {
        return Result.err(mapped.error);
      }
      final Object? key = row['name_key'];
      if (current.isNotEmpty && key != currentKey) {
        groups.add(DuplicateNameGroup(List<User>.unmodifiable(current)));
        current = <User>[];
      }
      currentKey = key;
      current.add((mapped as Ok<User>).value);
    }
    if (current.isNotEmpty) {
      groups.add(DuplicateNameGroup(List<User>.unmodifiable(current)));
    }
    return Result.ok(List<DuplicateNameGroup>.unmodifiable(groups));
  }

  static Result<User> _mapUser(Map<String, dynamic> row) {
    final idResult = UserId.tryParse(row['id']?.toString());
    if (idResult is Err<UserId>) {
      return Result.err(_corrupt('id'));
    }
    final roleResult = PlatformRole.tryParse(row['role']?.toString());
    if (roleResult is Err<PlatformRole>) {
      return Result.err(_corrupt('role'));
    }
    final UserStatus status;
    switch (row['status']?.toString()) {
      case 'active':
        status = UserStatus.active;
      case 'suspended':
        status = UserStatus.suspended;
      default:
        return Result.err(_corrupt('status'));
    }
    return Result.ok(
      User(
        id: (idResult as Ok<UserId>).value,
        email: row['email'] as String?,
        role: (roleResult as Ok<PlatformRole>).value,
        status: status,
        displayName: (row['display_name'] as String?) ?? '',
      ),
    );
  }

  static AppError _corrupt(String field) => AppError.transient(
    'identity.row_corrupt',
    'A duplicate-name row has an invalid $field',
  );
}
