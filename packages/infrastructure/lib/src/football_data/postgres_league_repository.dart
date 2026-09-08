import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [LeagueRepository] over `football_data.leagues`
/// (migration `0027_fixture_league.sql`).
///
/// Total (Application ADR Section 2): never throws. Read-only, exactly like
/// its team sibling.
final class PostgresLeagueRepository implements LeagueRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresLeagueRepository(this._connection);

  final PostgresConnection _connection;

  static const String _listAllSql = '''
SELECT id, name, short_name, logo_url
FROM football_data.leagues
ORDER BY name ASC, id ASC
''';

  @override
  Future<Result<List<League>>> listAll() async {
    final result = await _connection.query(_listAllSql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapAll(value),
    };
  }

  Result<List<League>> _mapAll(List<Map<String, dynamic>> rows) {
    final leagues = <League>[];
    for (final row in rows) {
      final mapped = _mapRow(row);
      if (mapped is Err<League>) {
        return Result.err(mapped.error);
      }
      leagues.add((mapped as Ok<League>).value);
    }
    return Result.ok(List<League>.unmodifiable(leagues));
  }

  Result<League> _mapRow(Map<String, dynamic> row) {
    final idResult = LeagueRef.tryParse(row['id']?.toString());
    if (idResult is Err<LeagueRef>) {
      return Result.err(_corrupt('id', idResult.error.message));
    }
    final name = row['name'];
    if (name is! String) {
      return Result.err(_corrupt('name', 'not a string'));
    }
    return Result.ok(
      League(
        id: (idResult as Ok<LeagueRef>).value,
        name: name,
        shortName: row['short_name'] as String?,
        logoUrl: row['logo_url'] as String?,
      ),
    );
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'football_data.row_corrupt',
    'Stored football_data.leagues row has invalid $field: $detail',
  );
}
