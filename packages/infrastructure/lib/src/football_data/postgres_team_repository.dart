import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [TeamRepository] over the `football_data.teams` table
/// (migration `0013_football_data.sql`).
///
/// Total (Application ADR §2): never throws — every outcome is a typed
/// [Result]. Read-only: nothing writes `football_data.teams` from the
/// application layer yet (populated by seed data, Football Data phase).
final class PostgresTeamRepository implements TeamRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresTeamRepository(this._connection);

  final PostgresConnection _connection;

  static const String _listAllSql = '''
SELECT id, name, short_name, crest_url
FROM football_data.teams
ORDER BY name ASC, id ASC
''';

  @override
  Future<Result<List<Team>>> listAll() async {
    final result = await _connection.query(_listAllSql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapAll(value),
    };
  }

  Result<List<Team>> _mapAll(List<Map<String, dynamic>> rows) {
    final teams = <Team>[];
    for (final row in rows) {
      final mapped = _mapRow(row);
      if (mapped is Err<Team>) {
        return Result.err(mapped.error);
      }
      teams.add((mapped as Ok<Team>).value);
    }
    return Result.ok(List<Team>.unmodifiable(teams));
  }

  Result<Team> _mapRow(Map<String, dynamic> row) {
    final idResult = TeamRef.tryParse(row['id']?.toString());
    if (idResult is Err<TeamRef>) {
      return Result.err(_corrupt('id', idResult.error.message));
    }
    final name = row['name'];
    if (name is! String) {
      return Result.err(_corrupt('name', 'not a string'));
    }
    return Result.ok(
      Team(
        id: (idResult as Ok<TeamRef>).value,
        name: name,
        shortName: row['short_name'] as String?,
        crestUrl: row['crest_url'] as String?,
      ),
    );
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'football_data.row_corrupt',
    'Stored football_data.teams row has invalid $field: $detail',
  );
}
