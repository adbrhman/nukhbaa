import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [WeeklyLeagueProfileReader] (P2-7b).
///
/// One statement over `identity.users` for the whole group, so a group of
/// twenty costs one round trip.
///
/// **It never selects the picture's bytes.** The table needs only whether a
/// picture exists and which version it is (`avatar_updated_at`, the cache key
/// of its URL), so the `avatar_bytes` column is not named here: twenty rows
/// must not drag twenty images across the wire.
///
/// A picture exists only when `avatar_mime` is set; migration
/// `0033_avatars_inline.sql` keeps bytes, mime and version all set or all
/// null, so `avatar_mime` decides and `avatar_updated_at` is its version.
///
/// A row that cannot be decoded is dropped, not escalated: a name is how the
/// table draws a row, and one malformed row must not cost twenty players
/// their standings. The use-case then carries that member without a profile.
///
/// Total (Application ADR, Section 2): never throws, binds every value
/// through a `@named` parameter (Security ADR, Section 2).
final class PostgresWeeklyLeagueProfileReader
    implements WeeklyLeagueProfileReader {
  /// Creates the reader over [_connection].
  const PostgresWeeklyLeagueProfileReader(this._connection);

  final PostgresConnection _connection;

  static const String _profilesSql = '''
SELECT u.id::text AS user_id,
       u.display_name AS display_name,
       CASE WHEN u.avatar_mime IS NOT NULL
            THEN u.avatar_updated_at
       END AS avatar_updated_at
FROM identity.users u
WHERE u.id = ANY(@ids)
''';

  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const Result.ok({});
    }
    final result = await _connection.query(
      _profilesSql,
      parameters: {
        'ids': [for (final id in userIds) id.value],
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(_mapAll(value)),
    };
  }

  static Map<UserId, WeeklyLeagueMemberProfile> _mapAll(
    List<Map<String, dynamic>> rows,
  ) {
    final profiles = <UserId, WeeklyLeagueMemberProfile>{};
    for (final row in rows) {
      final userResult = UserId.tryParse(row['user_id']?.toString());
      final name = row['display_name']?.toString().trim() ?? '';
      if (userResult is! Ok<UserId> || name.isEmpty) {
        continue;
      }
      profiles[userResult.value] = WeeklyLeagueMemberProfile(
        displayName: name,
        avatarUpdatedAt: _readTimestamp(row['avatar_updated_at']),
      );
    }
    return Map<UserId, WeeklyLeagueMemberProfile>.unmodifiable(profiles);
  }

  static DateTime? _readTimestamp(Object? raw) {
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return DateTime.tryParse(raw?.toString() ?? '')?.toUtc();
  }
}
