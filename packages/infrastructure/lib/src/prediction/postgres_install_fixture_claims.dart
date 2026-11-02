import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [InstallFixtureClaims] over `prediction.install_claims`
/// (migration 0197, script 200).
///
/// One statement claims the match on the install when no account holds it
/// there, and answers the holder: the row it inserted, or the one already
/// there. It also records the account on the install
/// (`identity.install_accounts`), so the admin sees a phone a player
/// predicts from. The install id is stored as md5 only.
///
/// Two first claims at the same moment: the second waits for the first and
/// inserts nothing, and its statement cannot see the first's row (it began
/// before that row was committed). It then reads the holder once more.
///
/// Total: never throws; a malformed row is a transient
/// `prediction.row_corrupt`.
final class PostgresInstallFixtureClaims implements InstallFixtureClaims {
  /// Creates the store over an open [PostgresConnection].
  const PostgresInstallFixtureClaims(this._connection);

  final PostgresConnection _connection;

  static const String _claimSql = '''
WITH seen AS (
  INSERT INTO identity.install_accounts (install_key, user_id)
  VALUES (md5(@install::text), @user_id::uuid)
  ON CONFLICT (install_key, user_id) DO UPDATE
    SET last_seen = now()
),
claimed AS (
  INSERT INTO prediction.install_claims (install_key, fixture_id, user_id)
  VALUES (md5(@install::text), @fixture_id::uuid, @user_id::uuid)
  ON CONFLICT (install_key, fixture_id) DO NOTHING
  RETURNING user_id
)
SELECT user_id::text AS user_id FROM claimed
UNION ALL
SELECT user_id::text
FROM prediction.install_claims
WHERE install_key = md5(@install::text)
  AND fixture_id = @fixture_id::uuid
LIMIT 1
''';

  static const String _holderSql = '''
SELECT user_id::text AS user_id
FROM prediction.install_claims
WHERE install_key = md5(@install::text)
  AND fixture_id = @fixture_id::uuid
''';

  @override
  Future<Result<UserId>> claim({
    required String installId,
    required FixtureRef fixture,
    required UserId userId,
  }) async {
    final first = await _connection.query(
      _claimSql,
      parameters: {
        'install': installId,
        'fixture_id': fixture.value,
        'user_id': userId.value,
      },
    );
    if (first is Err<List<Map<String, dynamic>>>) {
      return Result.err(first.error);
    }
    var rows = (first as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      final again = await _connection.query(
        _holderSql,
        parameters: {'install': installId, 'fixture_id': fixture.value},
      );
      if (again is Err<List<Map<String, dynamic>>>) {
        return Result.err(again.error);
      }
      rows = (again as Ok<List<Map<String, dynamic>>>).value;
    }
    if (rows.isEmpty) {
      return const Result.err(
        AppError.transient(
          'prediction.row_corrupt',
          'An install claim was neither made nor found',
        ),
      );
    }
    final holder = UserId.tryParse(rows.first['user_id']?.toString());
    return switch (holder) {
      Ok<UserId>() => holder,
      Err<UserId>() => const Result.err(
        AppError.transient(
          'prediction.row_corrupt',
          'An install claim has an invalid user_id',
        ),
      ),
    };
  }
}
