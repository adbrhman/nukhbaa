import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [PushOpenRepository] (migration 0069).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter.
final class PostgresPushOpenRepository implements PushOpenRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresPushOpenRepository(this._connection);

  final PostgresConnection _connection;

  static const String _insertSql = '''
INSERT INTO notification.push_opens (user_id, link, opened_at)
VALUES (@user_id, @link, @opened_at)
''';

  @override
  Future<Result<void>> record({
    required UserId userId,
    required String link,
    required DateTime openedAt,
  }) async {
    final result = await _connection.query(
      _insertSql,
      parameters: {
        'user_id': userId.value,
        'link': link,
        'opened_at': openedAt.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }
}
