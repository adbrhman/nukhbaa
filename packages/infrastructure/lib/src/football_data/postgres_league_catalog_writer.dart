import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres [LeagueCatalogWriter] over `football_data.leagues` (script 139).
///
/// One transaction: an advisory lock on the name's spelling key
/// (`competition.team_name_key`, migration 0110), then the league already
/// filed under that key, and only when there is none a new row -- so two
/// admins adding one league at the same moment add it once. The new row is
/// continental (migration 0038: its clubs come from the whole catalog, as
/// 0104's derbies) and has no logo and no short name. Tested in
/// supabase/tests/league_catalog_add_query_test.sql.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresLeagueCatalogWriter implements LeagueCatalogWriter {
  /// Creates the writer over [_connection].
  const PostgresLeagueCatalogWriter(this._connection);

  final PostgresConnection _connection;

  // Held until the transaction ends.
  static const String _lockSql = '''
SELECT pg_advisory_xact_lock(
  hashtext('football_data.league:' || competition.team_name_key(@name::text))
)
''';

  static const String _existingSql = '''
SELECT l.id::text AS id,
       l.name,
       l.short_name,
       l.logo_url,
       l.is_continental
FROM football_data.leagues l
WHERE competition.team_name_key(l.name) = competition.team_name_key(@name::text)
ORDER BY l.created_at, l.id
LIMIT 1
''';

  static const String _insertSql = '''
INSERT INTO football_data.leagues (name, is_continental)
VALUES (@name::text, true)
RETURNING id::text AS id, name, short_name, logo_url, is_continental
''';

  @override
  Future<Result<LeagueAddition>> add({required String name}) {
    return _connection.runInTransaction<LeagueAddition>((tx) async {
      final locked = await tx.query(_lockSql, parameters: {'name': name});
      if (locked is Err<List<Map<String, dynamic>>>) {
        return Result.err(locked.error);
      }

      final existing = await tx.query(_existingSql, parameters: {'name': name});
      if (existing is Err<List<Map<String, dynamic>>>) {
        return Result.err(existing.error);
      }
      final found = (existing as Ok<List<Map<String, dynamic>>>).value;
      if (found.isNotEmpty) {
        return _addition(found.first, existed: true);
      }

      final inserted = await tx.query(_insertSql, parameters: {'name': name});
      if (inserted is Err<List<Map<String, dynamic>>>) {
        return Result.err(inserted.error);
      }
      final rows = (inserted as Ok<List<Map<String, dynamic>>>).value;
      if (rows.isEmpty) {
        return Result.err(_corrupt('row', 'the insert answered no row'));
      }
      return _addition(rows.first, existed: false);
    });
  }

  static Result<LeagueAddition> _addition(
    Map<String, dynamic> row, {
    required bool existed,
  }) {
    final idResult = LeagueRef.tryParse(row['id']?.toString());
    if (idResult is Err<LeagueRef>) {
      return Result.err(_corrupt('id', idResult.error.message));
    }
    final name = row['name'];
    if (name is! String) {
      return Result.err(_corrupt('name', 'not a string'));
    }
    final shortName = row['short_name'];
    final logoUrl = row['logo_url'];
    return Result.ok(
      LeagueAddition(
        league: League(
          id: (idResult as Ok<LeagueRef>).value,
          name: name,
          shortName: shortName is String ? shortName : null,
          logoUrl: logoUrl is String ? logoUrl : null,
          isContinental: row['is_continental'] == true,
        ),
        existed: existed,
      ),
    );
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'football_data.row_corrupt',
    'Stored football_data.leagues row has invalid $field: $detail',
  );
}
