import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixtureScheduleRepository] over the
/// `competition.fixture_schedules` table (migration `0012_fixture_schedule.sql`).
///
/// Storage side of the fixture IDENTITY seam (Next-Task decision 2026-07-11,
/// option (a), applied to schedule rather than outcome): admin-fed, keyed by
/// fixture id only, no competition/round reference (Axiom 3).
///
/// Total (Application ADR §2): never throws — every outcome is a typed
/// [Result]. All queries bind through `@named` parameters (Security ADR §2).
final class PostgresFixtureScheduleRepository
    implements FixtureScheduleRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixtureScheduleRepository(this._connection);

  final PostgresConnection _connection;

  // --------------------------------------------------------------------------
  // upsert — admin registration/correction (idempotent per fixture)
  // --------------------------------------------------------------------------

  static const String _upsertSql = '''
INSERT INTO competition.fixture_schedules
  (fixture_id, home_team, away_team, kickoff_at)
VALUES (@fixture_id, @home_team, @away_team, @kickoff_at)
ON CONFLICT (fixture_id) DO UPDATE SET
  home_team  = EXCLUDED.home_team,
  away_team  = EXCLUDED.away_team,
  kickoff_at = EXCLUDED.kickoff_at
''';

  @override
  Future<Result<void>> upsert(FixtureSchedule schedule) async {
    final inserted = await _connection.query(
      _upsertSql,
      parameters: {
        'fixture_id': schedule.fixture.value,
        'home_team': schedule.homeTeam,
        'away_team': schedule.awayTeam,
        'kickoff_at': schedule.kickoffAt.toUtc().toIso8601String(),
      },
    );
    return switch (inserted) {
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
    };
  }

  // --------------------------------------------------------------------------
  // findByFixture — single-fixture read (Ok(null) when none registered)
  // --------------------------------------------------------------------------

  static const String _selectByFixtureSql = '''
SELECT fixture_id, home_team, away_team, kickoff_at
FROM competition.fixture_schedules
WHERE fixture_id = @fixture_id
''';

  @override
  Future<Result<FixtureSchedule?>> findByFixture(FixtureRef fixture) async {
    final result = await _connection.query(
      _selectByFixtureSql,
      parameters: {'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapOne(value.first),
    };
  }

  // --------------------------------------------------------------------------
  // findByFixtures — batch read; absent fixtures are simply omitted
  // --------------------------------------------------------------------------

  static const String _selectByFixturesSql = '''
SELECT fixture_id, home_team, away_team, kickoff_at
FROM competition.fixture_schedules
WHERE fixture_id = ANY(@fixture_ids)
''';

  @override
  Future<Result<List<FixtureSchedule>>> findByFixtures(
    List<FixtureRef> fixtures,
  ) async {
    if (fixtures.isEmpty) {
      return const Result.ok(<FixtureSchedule>[]);
    }
    final result = await _connection.query(
      _selectByFixturesSql,
      parameters: {
        'fixture_ids': [for (final f in fixtures) f.value],
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapMany(value),
    };
  }

  // --------------------------------------------------------------------------
  // Row mapping
  // --------------------------------------------------------------------------

  Result<FixtureSchedule?> _mapOne(Map<String, dynamic> row) {
    final mapped = _mapRow(row);
    return switch (mapped) {
      Ok<FixtureSchedule>(:final value) => Result.ok(value),
      Err<FixtureSchedule>(:final error) => Result.err(error),
    };
  }

  Result<List<FixtureSchedule>> _mapMany(List<Map<String, dynamic>> rows) {
    final results = <FixtureSchedule>[];
    for (final row in rows) {
      final mapped = _mapRow(row);
      if (mapped is Err<FixtureSchedule>) {
        return Result.err(mapped.error);
      }
      results.add((mapped as Ok<FixtureSchedule>).value);
    }
    return Result.ok(List<FixtureSchedule>.unmodifiable(results));
  }

  Result<FixtureSchedule> _mapRow(Map<String, dynamic> row) {
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final homeTeam = row['home_team'];
    final awayTeam = row['away_team'];
    final kickoffAt = row['kickoff_at'];

    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(
        _corrupt(
          'fixture_schedules',
          'fixture_id',
          fixtureResult.error.message,
        ),
      );
    }
    if (homeTeam is! String) {
      return Result.err(
        _corrupt('fixture_schedules', 'home_team', 'not a string'),
      );
    }
    if (awayTeam is! String) {
      return Result.err(
        _corrupt('fixture_schedules', 'away_team', 'not a string'),
      );
    }
    if (kickoffAt is! DateTime) {
      return Result.err(
        _corrupt('fixture_schedules', 'kickoff_at', 'not a timestamp'),
      );
    }
    return Result.ok(
      FixtureSchedule.fromStored(
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        kickoffAt: kickoffAt,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Error reclassification
  // --------------------------------------------------------------------------

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    // 23514 check_violation — team-name length or "teams must differ" backstop
    // (Axiom 6), mirroring FixtureSchedule.create's own validation.
    if (cause.code == '23514') {
      return const AppError.invariant(
        'competition.fixture_schedule_integrity_violation',
        'The fixture schedule violated an integrity rule',
      );
    }
    return error;
  }

  static AppError _corrupt(String table, String field, String detail) =>
      AppError.transient(
        'competition.row_corrupt',
        'Stored $table row has invalid $field: $detail',
      );
}
