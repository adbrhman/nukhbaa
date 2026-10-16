import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres [TeamCatalogWriter] over `football_data.teams` (script 91).
///
/// One transaction: an advisory lock on the name's spelling key
/// (`competition.team_name_key`, migration 0110), then a blocked name
/// refused (`football_data.is_blocked_club`, migration 0174), then the club
/// already filed under that key, and only when there is none a new row --
/// so two admins adding one club at the same moment add it once. The new row has
/// no crest and no short name. Tested in
/// supabase/tests/team_catalog_add_query_test.sql.
///
/// Total: never throws, binds every value through a `@named` parameter.
final class PostgresTeamCatalogWriter implements TeamCatalogWriter {
  /// Creates the writer over [_connection].
  const PostgresTeamCatalogWriter(this._connection);

  final PostgresConnection _connection;

  // Held until the transaction ends.
  static const String _lockSql = '''
SELECT pg_advisory_xact_lock(
  hashtext('football_data.team:' || competition.team_name_key(@name::text))
)
''';

  static const String _blockedSql = '''
SELECT football_data.is_blocked_club(@name::text) AS blocked
''';

  static const String _existingSql = '''
SELECT t.id::text AS id,
       t.name,
       t.short_name,
       t.crest_url,
       t.league_id::text AS league_id
FROM football_data.teams t
WHERE competition.team_name_key(t.name) = competition.team_name_key(@name::text)
ORDER BY t.created_at, t.id
LIMIT 1
''';

  static const String _insertSql = '''
INSERT INTO football_data.teams (name, league_id)
VALUES (@name::text, @league_id::uuid)
RETURNING id::text AS id, name, short_name, crest_url, league_id::text AS league_id
''';

  @override
  Future<Result<TeamAddition>> add({
    required String name,
    required LeagueRef? leagueId,
  }) {
    return _connection.runInTransaction<TeamAddition>((tx) async {
      final locked = await tx.query(_lockSql, parameters: {'name': name});
      if (locked is Err<List<Map<String, dynamic>>>) {
        return Result.err(locked.error);
      }

      final blocked = await tx.query(_blockedSql, parameters: {'name': name});
      if (blocked is Err<List<Map<String, dynamic>>>) {
        return Result.err(blocked.error);
      }
      final blockedRows = (blocked as Ok<List<Map<String, dynamic>>>).value;
      if (blockedRows.isNotEmpty && blockedRows.first['blocked'] == true) {
        return const Result.err(AdminAddTeam.blocked);
      }

      final existing = await tx.query(_existingSql, parameters: {'name': name});
      if (existing is Err<List<Map<String, dynamic>>>) {
        return Result.err(existing.error);
      }
      final found = (existing as Ok<List<Map<String, dynamic>>>).value;
      if (found.isNotEmpty) {
        return _addition(found.first, existed: true);
      }

      final inserted = await tx.query(
        _insertSql,
        parameters: {'name': name, 'league_id': leagueId?.value},
      );
      if (inserted is Err<List<Map<String, dynamic>>>) {
        final cause = inserted.error.cause;
        // The catalog's own guard (0174), should a name slip past the check.
        if (cause is ServerException &&
            cause.constraintName == 'teams_blocked_club') {
          return const Result.err(AdminAddTeam.blocked);
        }
        return Result.err(inserted.error);
      }
      final rows = (inserted as Ok<List<Map<String, dynamic>>>).value;
      if (rows.isEmpty) {
        return Result.err(_corrupt('row', 'the insert answered no row'));
      }
      return _addition(rows.first, existed: false);
    });
  }

  static Result<TeamAddition> _addition(
    Map<String, dynamic> row, {
    required bool existed,
  }) {
    final idResult = TeamRef.tryParse(row['id']?.toString());
    if (idResult is Err<TeamRef>) {
      return Result.err(_corrupt('id', idResult.error.message));
    }
    final name = row['name'];
    if (name is! String) {
      return Result.err(_corrupt('name', 'not a string'));
    }
    final shortName = row['short_name'];
    final crestUrl = row['crest_url'];
    final leagueIdRaw = row['league_id']?.toString();
    LeagueRef? league;
    if (leagueIdRaw != null) {
      final parsed = LeagueRef.tryParse(leagueIdRaw);
      if (parsed is Err<LeagueRef>) {
        return Result.err(_corrupt('league_id', parsed.error.message));
      }
      league = (parsed as Ok<LeagueRef>).value;
    }
    return Result.ok(
      TeamAddition(
        team: Team(
          id: (idResult as Ok<TeamRef>).value,
          name: name,
          shortName: shortName is String ? shortName : null,
          crestUrl: crestUrl is String ? crestUrl : null,
          leagueId: league,
        ),
        existed: existed,
      ),
    );
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'football_data.row_corrupt',
    'Stored football_data.teams row has invalid $field: $detail',
  );
}
