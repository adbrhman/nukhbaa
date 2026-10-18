import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// [AccountDeletion] over `identity.delete_account` (migration 0178).
///
/// Total: never throws, binds the id through a `@named` parameter. After the
/// call, successful or not, [_onDeleted] drops the account from the server's
/// user cache, so its next request is refused at once (a write that errored
/// may still have landed).
final class PostgresAccountDeletion implements AccountDeletion {
  /// Creates the adapter over [_connection].
  const PostgresAccountDeletion(
    this._connection, {
    required void Function(UserId id) onDeleted,
  }) : _onDeleted = onDeleted;

  final PostgresConnection _connection;
  final void Function(UserId id) _onDeleted;

  static const String _deleteSql = '''
SELECT identity.delete_account(@user_id::uuid) AS deleted
''';

  @override
  Future<Result<bool>> anonymise(UserId userId) async {
    final Result<List<Map<String, dynamic>>> result = await _connection.query(
      _deleteSql,
      parameters: {'user_id': userId.value},
    );
    _onDeleted(userId);
    return switch (result) {
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty && value.first['deleted'] == true,
      ),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
    };
  }
}
