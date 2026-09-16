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

  @override
  Future<Result<Map<String, String>>> canonicalIds({
    required String source,
    required String table,
    required List<String> externalIds,
  }) async {
    if (externalIds.isEmpty) {
      return const Result.ok(<String, String>{});
    }
    final result = await _connection.query(
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
    final result = await _connection.query(
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
    final result = await _connection.query(
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
