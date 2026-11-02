import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [SupportConversationOpener] over `support.conversations`
/// (migration 0187, one per player; script 202).
///
/// One statement opens the player's conversation when he has none and
/// answers its id either way. Two openings at the same moment: the second
/// inserts nothing and cannot see the first's row, so it reads once more.
/// An account that does not exist (the foreign key) is the invariant
/// `support.player_not_found`.
final class PostgresSupportConversationOpener
    implements SupportConversationOpener {
  /// Creates the opener over an open [PostgresConnection].
  const PostgresSupportConversationOpener(this._connection);

  final PostgresConnection _connection;

  static const String _openSql = '''
WITH opened AS (
  INSERT INTO support.conversations (player_id)
  VALUES (@player_id::uuid)
  ON CONFLICT (player_id) DO NOTHING
  RETURNING id
)
SELECT id::text AS id FROM opened
UNION ALL
SELECT id::text FROM support.conversations WHERE player_id = @player_id::uuid
LIMIT 1
''';

  static const String _findSql = '''
SELECT id::text AS id FROM support.conversations WHERE player_id = @player_id::uuid
''';

  static const AppError _notFound = AppError.invariant(
    'support.player_not_found',
    'الحساب غير موجود.',
  );

  @override
  Future<Result<SupportConversationId>> openFor(UserId playerId) async {
    final Map<String, Object?> parameters = {'player_id': playerId.value};
    final first = await _connection.query(_openSql, parameters: parameters);
    if (first is Err<List<Map<String, dynamic>>>) {
      final Object? cause = first.error.cause;
      if (cause is ServerException && cause.code == '23503') {
        return const Result.err(_notFound);
      }
      return Result.err(first.error);
    }
    var rows = (first as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      final again = await _connection.query(_findSql, parameters: parameters);
      if (again is Err<List<Map<String, dynamic>>>) {
        return Result.err(again.error);
      }
      rows = (again as Ok<List<Map<String, dynamic>>>).value;
    }
    if (rows.isEmpty) {
      return const Result.err(
        AppError.transient(
          'support.row_corrupt',
          'A conversation was neither opened nor found',
        ),
      );
    }
    final id = SupportConversationId.tryParse(rows.first['id']?.toString());
    return switch (id) {
      Ok<SupportConversationId>() => id,
      Err<SupportConversationId>() => const Result.err(
        AppError.transient(
          'support.row_corrupt',
          'A conversation has an invalid id',
        ),
      ),
    };
  }
}
