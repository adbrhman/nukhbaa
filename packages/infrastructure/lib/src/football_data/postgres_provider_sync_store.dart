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
       s.league_id::text AS league_id,
       s.home_team || ' - ' || s.away_team AS game
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
  // a side typed by hand is compared by its normalised name -- equal, or
  // one containing the other, three letters at least. A side with a team
  // on file is compared by that team only, both sides must agree, and a
  // fixture already linked to a provider match is never adopted again
  // (audit C-04). Tested in
  // supabase/tests/provider_sync_existing_fixture_query_test.sql.
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
    -- A test fixture is never the real match a provider reports (0098).
    AND NOT s.is_test
    -- A fixture already linked to a provider match is that match, never
    -- this one (audit C-04: a second link let one result land on both).
    AND NOT EXISTS (
      SELECT 1
      FROM football_data.external_identity_map m
      WHERE m.canonical_table = 'fixture'
        AND m.canonical_id = s.fixture_id
    )
),
sides AS (
  SELECT c.fixture_id,
         c.kickoff_at,
         COALESCE(c.home_team_id = @home_id::uuid, false) AS home_id_same,
         COALESCE(c.away_team_id = @away_id::uuid, false) AS away_id_same,
         c.home_team_id IS NULL AS home_untyped,
         c.away_team_id IS NULL AS away_untyped,
         -- A side with a team on file is that team and no other, whatever
         -- its name says (audit C-04: a name can sit inside another club name).
         -- Only a side without one is matched by its normalised name:
         -- equal, or one inside the other, three letters at least.
         CASE
           WHEN c.home_team_id IS NOT NULL THEN c.home_team_id = @home_id::uuid
           ELSE c.h = t.h
             OR (length(t.h) >= 3 AND length(c.h) >= 3
                 AND (strpos(t.h, c.h) > 0 OR strpos(c.h, t.h) > 0))
         END AS home_same,
         CASE
           WHEN c.away_team_id IS NOT NULL THEN c.away_team_id = @away_id::uuid
           ELSE c.a = t.a
             OR (length(t.a) >= 3 AND length(c.a) >= 3
                 AND (strpos(t.a, c.a) > 0 OR strpos(c.a, t.a) > 0))
         END AS away_same,
         abs(extract(epoch from (c.kickoff_at - @kickoff::timestamptz))) AS gap
  FROM candidates c, target t
)
SELECT s.fixture_id::text AS fixture_id
FROM sides s
WHERE (s.home_same AND s.away_same)
   -- One side certain by its team, the other typed by hand with no team
   -- on file under a name the catalog does not use, within three hours.
   OR (s.gap <= 10800
       AND ((s.home_id_same AND s.away_untyped)
         OR (s.away_id_same AND s.home_untyped)))
ORDER BY (s.home_id_same AND s.away_id_same) DESC,
         (s.home_same AND s.away_same) DESC,
         s.gap,
         s.fixture_id
LIMIT 1
''';

  static const String _lastRunSql = '''
SELECT last_success_at
FROM football_data.sync_runs
WHERE job = @job
''';

  static const String _markRunSql = '''
INSERT INTO football_data.sync_runs (job, last_success_at)
VALUES (@job, @at::timestamptz)
ON CONFLICT (job) DO UPDATE
  SET last_success_at = excluded.last_success_at, updated_at = now()
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
    required DateTime kickoffAt,
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
        'kickoff': kickoffAt.toUtc().toIso8601String(),
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
  Future<Result<DateTime?>> lastSyncAt(String job) async {
    final result = await _queryWithRetry(_lastRunSql, parameters: {'job': job});
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty || value.first['last_success_at'] is! DateTime
            ? null
            : (value.first['last_success_at']! as DateTime).toUtc(),
      ),
    };
  }

  @override
  Future<Result<void>> markSyncAt(String job, DateTime at) async {
    final result = await _queryWithRetry(
      _markRunSql,
      parameters: {'job': job, 'at': at.toUtc().toIso8601String()},
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
              game: row['game']?.toString() ?? '',
            ),
          );
        }
        return Result.ok(pending);
    }
  }
}
