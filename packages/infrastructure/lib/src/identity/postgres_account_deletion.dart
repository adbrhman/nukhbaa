import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/support/supabase_image_store.dart';
import 'package:shared/shared.dart';

/// [AccountDeletion] over `identity.delete_account` (migration 0178).
///
/// Total: never throws, binds the id through a `@named` parameter. After the
/// call, successful or not, [_onDeleted] drops the account from the server's
/// user cache, so its next request is refused at once (a write that errored
/// may still have landed).
///
/// With an [SupportImageEraser], the support pictures kept in Storage are
/// removed once the account is deleted (script 223): migration 0187 drops the
/// conversation rows, and nothing else would remove the files.
final class PostgresAccountDeletion implements AccountDeletion {
  /// Creates the adapter over [_connection].
  const PostgresAccountDeletion(
    this._connection, {
    required void Function(UserId id) onDeleted,
    SupportImageEraser? images,
  }) : _onDeleted = onDeleted,
       _images = images;

  final PostgresConnection _connection;
  final void Function(UserId id) _onDeleted;
  final SupportImageEraser? _images;

  static const String _deleteSql = '''
SELECT identity.delete_account(@user_id::uuid) AS deleted
''';

  static const String _picturesSql = '''
SELECT m.image_path
  FROM support.messages m
  JOIN support.conversations c ON c.id = m.conversation_id
 WHERE c.player_id = @user_id::uuid
   AND m.image_path IS NOT NULL
''';

  /// The Storage paths of the player's support pictures, read BEFORE the
  /// deletion (it drops the rows that hold them).
  Future<List<String>> _pictures(UserId userId) async {
    if (_images == null) {
      return const <String>[];
    }
    final Result<List<Map<String, dynamic>>> rows = await _connection.query(
      _picturesSql,
      parameters: {'user_id': userId.value},
    );
    return switch (rows) {
      Ok<List<Map<String, dynamic>>>(:final value) => <String>[
        for (final Map<String, dynamic> row in value)
          if (row['image_path'] case final String path when path.isNotEmpty)
            path,
      ],
      Err<List<Map<String, dynamic>>>() => const <String>[],
    };
  }

  @override
  Future<Result<bool>> anonymise(UserId userId) async {
    final List<String> pictures = await _pictures(userId);
    final Result<List<Map<String, dynamic>>> result = await _connection.query(
      _deleteSql,
      parameters: {'user_id': userId.value},
    );
    _onDeleted(userId);
    final Result<bool> answer = switch (result) {
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty && value.first['deleted'] == true,
      ),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
    };
    // Best effort: a refused or unreachable Storage never fails a deletion
    // that already landed.
    final SupportImageEraser? images = _images;
    if (images != null &&
        pictures.isNotEmpty &&
        answer is Ok<bool> &&
        answer.value) {
      await images.erase(pictures);
    }
    return answer;
  }
}
