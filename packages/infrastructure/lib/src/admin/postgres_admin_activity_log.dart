import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

// NK300_04
/// Postgres-backed [AdminActivityLog] over `admin.admin_activity_log`
/// (script 300, migration 0224): one row appended per change an admin
/// made; the owners' read joins the admin's name and the player or match
/// the path names, as they read now.
///
/// Total: never throws; a malformed row is a transient `admin.row_corrupt`.
final class PostgresAdminActivityLog implements AdminActivityLog {
  /// Creates the log over an open [PostgresConnection].
  const PostgresAdminActivityLog(this._connection);

  final PostgresConnection _connection;

  static const String _insertSql = '''
INSERT INTO admin.admin_activity_log (actor_id, method, path, status)
VALUES (@actor, @method, @path, @status)
''';

  /// Checked against the table by
  /// `supabase/tests/0224_admin_activity_log_test.sql`.
  static const String latestSql = r'''
SELECT l.id,
       coalesce(a.display_name, '') AS actor_name,
       l.method,
       l.path,
       l.occurred_at,
       coalesce(u.display_name, fs.home_team || ' × ' || fs.away_team) AS target,
       CASE WHEN fr.fixture_id IS NULL THEN NULL
            ELSE fr.home_goals::text || '-' || fr.away_goals::text END AS result
FROM admin.admin_activity_log l
JOIN identity.users a ON a.id = l.actor_id
LEFT JOIN LATERAL (
  SELECT (regexp_match(
    l.path,
    '.*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})'
  ))[1]::uuid AS id
) t ON true
LEFT JOIN identity.users u ON u.id = t.id
LEFT JOIN competition.fixture_schedules fs ON fs.fixture_id = t.id
LEFT JOIN scoring.fixture_results fr ON fr.fixture_id = t.id
ORDER BY l.occurred_at DESC, l.id DESC
LIMIT @limit
''';

  /// The longest path kept, the table's own bound.
  static const int maxPath = 300;

  @override
  Future<Result<void>> record({
    required UserId actor,
    required String method,
    required String path,
    required int status,
  }) async {
    final String kept = path.length > maxPath
        ? path.substring(0, maxPath)
        : path;
    final result = await _connection.query(
      _insertSql,
      parameters: {
        'actor': actor.value,
        'method': method,
        'path': kept,
        'status': status,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<List<AdminActivity>>> latest({int limit = 200}) async {
    final result = await _connection.query(
      latestSql,
      parameters: {'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<AdminActivity> out = <AdminActivity>[];
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
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
      if (id is! int ||
          actor is! String ||
          method is! String ||
          path is! String ||
          at == null) {
        return const Result.err(_corrupt);
      }
      out.add(
        AdminActivity(
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
    'An admin activity row is invalid',
  );
}
