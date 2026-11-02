import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [DeviceSightings] over `identity.install_accounts`
/// (migration 0197, script 200) and `notification.device_token_owners`
/// (migration 0177).
///
/// The install id is stored as md5 only, as 0177 stores the push token: a
/// grouping key, never shown. A phone in the admin list is an install, or a
/// push token (one token belongs to one install): the phones seen before
/// the app sent its install id are listed through their token. Two keys
/// with the very same accounts are one phone; a phone whose accounts are
/// all on a larger phone's list is left out.
///
/// Total: never throws; a malformed row is a transient
/// `identity.row_corrupt`.
final class PostgresDeviceSightings implements DeviceSightings {
  /// Creates the store over an open [PostgresConnection].
  const PostgresDeviceSightings(this._connection);

  final PostgresConnection _connection;

  static const String _recordSql = '''
INSERT INTO identity.install_accounts (install_key, user_id)
VALUES (md5(@install::text), @user_id::uuid)
ON CONFLICT (install_key, user_id) DO UPDATE
  SET last_seen = now()
''';

  static const String _sharedSql = '''
WITH sightings AS (
  SELECT 'i:' || install_key AS device_key, user_id, last_seen AS seen
  FROM identity.install_accounts
  UNION ALL
  SELECT 't:' || token_key, user_id, first_seen
  FROM notification.device_token_owners
),
devices AS (
  SELECT array_agg(DISTINCT user_id ORDER BY user_id) AS members,
         max(seen) AS last_seen
  FROM sightings
  GROUP BY device_key
  HAVING count(DISTINCT user_id) > 1
),
merged AS (
  SELECT members, max(last_seen) AS last_seen
  FROM devices
  GROUP BY members
),
phones AS (
  SELECT m.members, m.last_seen
  FROM merged m
  WHERE NOT EXISTS (
    SELECT 1
    FROM merged o
    WHERE o.members @> m.members
      AND o.members <> m.members
  )
  ORDER BY cardinality(m.members) DESC, m.last_seen DESC, m.members
  LIMIT @limit
)
SELECT p.members::text AS phone_key,
       p.last_seen,
       u.id::text AS id,
       u.email,
       u.role::text AS role,
       u.status::text AS status,
       u.display_name
FROM phones p
JOIN identity.users u
  ON u.id = ANY (p.members)
ORDER BY cardinality(p.members) DESC, p.last_seen DESC, p.members,
         u.created_at ASC, u.id
''';

  @override
  Future<Result<void>> record({
    required String installId,
    required UserId userId,
  }) async {
    final result = await _connection.query(
      _recordSql,
      parameters: {'install': installId, 'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<List<SharedDeviceGroup>>> sharedDevices({
    required int limit,
  }) async {
    final result = await _connection.query(
      _sharedSql,
      parameters: {'limit': limit},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _group(value),
    };
  }

  // Rows arrive ordered by phone, so consecutive rows with one key are one
  // phone.
  static Result<List<SharedDeviceGroup>> _group(
    List<Map<String, dynamic>> rows,
  ) {
    final groups = <SharedDeviceGroup>[];
    var current = <User>[];
    Object? currentKey;
    DateTime? currentSeen;
    for (final row in rows) {
      final mapped = _mapUser(row);
      if (mapped is Err<User>) {
        return Result.err(mapped.error);
      }
      final DateTime? seen = _time(row['last_seen']);
      if (seen == null) {
        return Result.err(_corrupt('last_seen'));
      }
      final Object? key = row['phone_key'];
      if (current.isNotEmpty && key != currentKey) {
        groups.add(
          SharedDeviceGroup(
            users: List<User>.unmodifiable(current),
            lastSeen: currentSeen!,
          ),
        );
        current = <User>[];
      }
      currentKey = key;
      currentSeen = seen;
      current.add((mapped as Ok<User>).value);
    }
    if (current.isNotEmpty) {
      groups.add(
        SharedDeviceGroup(
          users: List<User>.unmodifiable(current),
          lastSeen: currentSeen!,
        ),
      );
    }
    return Result.ok(List<SharedDeviceGroup>.unmodifiable(groups));
  }

  static DateTime? _time(Object? raw) => switch (raw) {
    final DateTime t => t.toUtc(),
    final String s => DateTime.tryParse(s)?.toUtc(),
    _ => null,
  };

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
    'A shared-device row has an invalid $field',
  );
}
