import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [OwnerAuditLog] over `admin.owner_audit_log` (script
/// 287, migration 0219): one row appended per change an owner seat made.
///
/// Total: never throws.
final class PostgresOwnerAuditLog implements OwnerAuditLog {
  /// Creates the log over an open [PostgresConnection].
  const PostgresOwnerAuditLog(this._connection);

  final PostgresConnection _connection;

  // NK287_02
  static const String _sql = '''
INSERT INTO admin.owner_audit_log (actor_id, method, path, status)
VALUES (@actor, @method, @path, @status)
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
      _sql,
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
}
