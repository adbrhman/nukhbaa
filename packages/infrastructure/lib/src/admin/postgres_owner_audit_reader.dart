import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

// NK342_01
/// Postgres-backed [OwnerAuditReader] (script 342, plan 339 to 348): what the
/// owner seats did, read over two tables as one list, newest first.
///
/// * `admin.owner_audit_log`: every request an owner made to `/owner`
///   (`source` is `owner`).
/// * `admin.admin_activity_log`: the changes an owner seat made inside the
///   admins' tools, only for actors listed in `admin.platform_owners`
///   (`source` is `admin`). The seat table, not `admin.active_owners`, so a
///   line stays the owner's if his seat is later disabled or removed.
///
/// Read only: no index, table or migration is added. Total: never throws; a
/// malformed row is a transient `admin.row_corrupt`.
final class PostgresOwnerAuditReader implements OwnerAuditReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresOwnerAuditReader(this._connection);

  final PostgresConnection _connection;

  /// Both tables as one list of lines. An admin-tools line finds its target
  /// and result the way `PostgresAdminActivityLog.latestSql` does. The
  /// `source` breaks ties after the time, because the two tables count
  /// their ids apart.
  static const String latestSql = r'''
WITH lines AS (
  SELECT 'owner'::text AS source,
         l.id,
         coalesce(u.display_name, '') AS actor_name,
         l.method,
         l.path,
         l.occurred_at,
         NULL::text AS target,
         NULL::text AS result
  FROM admin.owner_audit_log l
  JOIN identity.users u ON u.id = l.actor_id
  UNION ALL
  SELECT 'admin'::text,
         l.id,
         coalesce(a.display_name, ''),
         l.method,
         l.path,
         l.occurred_at,
         coalesce(u.display_name, fs.home_team || ' \u00d7 ' || fs.away_team),
         CASE WHEN fr.fixture_id IS NULL THEN NULL
              ELSE fr.home_goals::text || '-' || fr.away_goals::text END
  FROM admin.admin_activity_log l
  JOIN identity.users a ON a.id = l.actor_id
  JOIN admin.platform_owners o ON o.user_id = l.actor_id
  LEFT JOIN LATERAL (
    SELECT (regexp_match(
      l.path,
      '.*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
    ))[1]::uuid AS id
  ) t ON true
  LEFT JOIN identity.users u ON u.id = t.id
  LEFT JOIN competition.fixture_schedules fs ON fs.fixture_id = t.id
  LEFT JOIN scoring.fixture_results fr ON fr.fixture_id = t.id
)
SELECT source, id, actor_name, method, path, occurred_at, target, result
FROM lines
ORDER BY occurred_at DESC, source, id DESC
LIMIT @limit
''';

  @override
  Future<Result<List<OwnerAuditLine>>> latest({int limit = 200}) async {
    final result = await _connection.query(
      latestSql,
      parameters: {'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<OwnerAuditLine> out = <OwnerAuditLine>[];
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final Object? source = row['source'];
      final Object? id = row['id'];
      final Object? actor = row['actor_name'];
      final Object? method = row['method'];
      final Object? path = row['path'];
      final Object? target = row['target'];
      final Object? score = row['result'];
      final DateTime? at = switch (row['occurred_at']) {
        final DateTime t => t.toUtc(),
        final String s => DateTime.tryParse(s)?.toUtc(),
        _ => null,
      };
      if (source is! String ||
          (source != OwnerAuditLine.sourceOwner &&
              source != OwnerAuditLine.sourceAdmin) ||
          id is! int ||
          actor is! String ||
          method is! String ||
          path is! String ||
          at == null) {
        return const Result.err(_corrupt);
      }
      out.add(
        OwnerAuditLine(
          source: source,
          id: id,
          actorName: actor,
          method: method,
          path: path,
          at: at,
          target: target is String ? target : null,
          result: score is String ? score : null,
        ),
      );
    }
    return Result.ok(out);
  }

  static const AppError _corrupt = AppError.transient(
    'admin.row_corrupt',
    'An owner audit row is invalid',
  );
}
