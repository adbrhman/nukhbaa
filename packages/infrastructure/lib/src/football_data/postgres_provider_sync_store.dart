import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres adapter for [ProviderSyncStore] over
/// `football_data.external_identity_map` (migration 0013), joined to
/// `competition.fixture_schedules` and `scoring.fixture_results` for the
/// pending-results read.
final class PostgresProviderSyncStore implements ProviderSyncStore {
  /// Creates the store over [_connection].
  const PostgresProviderSyncStore(this._connection);

  final PostgresConnection _connection;

  static const String _canonicalSql = '''
SELECT external_id, canonical_id::text AS canonical_id
FROM football_data.external_identity_map
WHERE external_source = @source
  AND canonical_table = @table
  AND external_id = ANY(@ids::text[])
''';

  static const String _linkSql = '''
INSERT INTO football_data.external_identity_map
  (external_source, external_id, canonical_table, canonical_id)
VALUES (@source, @external_id, @table, @canonical_id::uuid)
ON CONFLICT (external_source, external_id, canonical_table) DO NOTHING
''';

  static const String _pendingSql = '''
SELECT m.canonical_id::text AS fixture_id,
       m.external_id,
       s.kickoff_at,
       s.league_id::text AS league_id
FROM football_data.external_identity_map m
JOIN competition.fixture_schedules s
  ON s.fixture_id = m.canonical_id
LEFT JOIN scoring.fixture_results r
  ON r.fixture_id = m.canonical_id
WHERE m.external_source = @source
  AND m.canonical_table = 'fixture'
  AND r.fixture_id IS NULL
  AND s.kickoff_at >= @from::timestamptz
  AND s.kickoff_at < @before::timestamptz
ORDER BY s.kickoff_at
LIMIT 200
''';

  // Hand-added fixtures often carry free-text names whose spelling differs
  // from the catalog (hamza forms, taa marbuta, spaces, a shorter name), so
  // names are compared normalised, equal or one containing the other, and
  // only when both normalised names have at least three letters.
  static const String _existingSql = '''
WITH target AS (
  SELECT regexp_replace(translate(btrim(@home_name::text), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS h,
         regexp_replace(translate(btrim(@away_name::text), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS a
),
candidates AS (
  SELECT s.fixture_id,
         s.kickoff_at,
         s.home_team_id,
         s.away_team_id,
         regexp_replace(translate(btrim(s.home_team), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS h,
         regexp_replace(translate(btrim(s.away_team), 'أإآٱىة', 'اااايه'), '[[:space:]]+', '', 'g') AS a
  FROM competition.fixture_schedules s
  WHERE s.kickoff_at >= @from::timestamptz
    AND s.kickoff_at < @to::timestamptz
)
SELECT c.fixture_id::text AS fixture_id
FROM candidates c, target t
WHERE (c.home_team_id = @home_id::uuid AND c.away_team_id = @away_id::uuid)
   OR (
        length(t.h) >= 3 AND length(t.a) >= 3
    AND length(c.h) >= 3 AND length(c.a) >= 3
    AND (c.h = t.h OR strpos(t.h, c.h) > 0 OR strpos(c.h, t.h) > 0)
    AND (c.a = t.a OR strpos(t.a, c.a) > 0 OR strpos(c.a, t.a) > 0)
   )
ORDER BY c.kickoff_at
LIMIT 1
''';

  /// One retry for background sync queries: the pool's first
  /// statement after an idle stretch can exceed the 10 s limit, and a
  /// lost poll would wait a whole tick. Request paths keep the
  /// single-shot behaviour.
  Future<Result<List<Map<String, dynamic>>>> _queryWithRetry(
    String sql, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    final first = await _connection.query(sql, parameters: parameters);
    if (first is Err<List<Map<String, dynamic>>> &&
        first.error.code == 'db.query_timeout') {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _connection.query(sql, parameters: parameters);
    }
    return first;
  }

  @override
  Future<Result<String?>> findExistingFixture({
    required String homeTeamId,
    required String awayTeamId,
    required String homeTeamName,
    required String awayTeamName,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _queryWithRetry(
      _existingSql,
      parameters: {
        'home_id': homeTeamId,
        'away_id': awayTeamId,
        'home_name': homeTeamName.trim(),
        'away_name': awayTeamName.trim(),
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty ? null : value.first['fixture_id'].toString(),
      ),
    };
  }

  @override
  Future<Result<Map<String, String>>> canonicalIds({
    required String source,
    required String table,
    required List<String> externalIds,
  }) async {
    if (externalIds.isEmpty) {
      return const Result.ok(<String, String>{});
    }
    final result = await _queryWithRetry(
      _canonicalSql,
      parameters: {
        'source': source,
        'table': table,
        'ids': externalIds.toSet().toList(growable: false),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok({
        for (final row in value)
          row['external_id'].toString(): row['canonical_id'].toString(),
      }),
    };
  }

  @override
  Future<Result<void>> link({
    required String source,
    required String table,
    required String externalId,
    required String canonicalId,
  }) async {
    final result = await _queryWithRetry(
      _linkSql,
      parameters: {
        'source': source,
        'table': table,
        'external_id': externalId,
        'canonical_id': canonicalId,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }

  @override
  Future<Result<List<PendingProviderFixture>>> fixturesAwaitingResult({
    required String source,
    required DateTime kickedOffFrom,
    required DateTime kickedOffBefore,
  }) async {
    final result = await _queryWithRetry(
      _pendingSql,
      parameters: {
        'source': source,
        'from': kickedOffFrom.toUtc().toIso8601String(),
        'before': kickedOffBefore.toUtc().toIso8601String(),
      },
    );
    switch (result) {
      case Err<List<Map<String, dynamic>>>(:final error):
        return Result.err(error);
      case Ok<List<Map<String, dynamic>>>(:final value):
        final pending = <PendingProviderFixture>[];
        for (final row in value) {
          final kickoff = row['kickoff_at'];
          if (kickoff is! DateTime) {
            return const Result.err(
              AppError.transient(
                'football_data.row_corrupt',
                'fixture_schedules.kickoff_at is not a timestamp',
              ),
            );
          }
          pending.add(
            PendingProviderFixture(
              fixtureId: row['fixture_id'].toString(),
              externalId: row['external_id'].toString(),
              kickoffAt: kickoff.toUtc(),
              leagueId: row['league_id']?.toString(),
            ),
          );
        }
        return Result.ok(pending);
    }
  }
}
