import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixtureScoreRepository] over `scoring.fixture_scores`
/// (Axiom 4 Amendment; migration
/// `0019_axiom4_fixture_prediction_scoring.sql`) — the per-fixture sibling of
/// [PostgresScoreRepository], collapsed to a single flat table since a
/// fixture score has no per-fixture children (it *is* the per-fixture row).
///
/// Atomicity/idempotency: [saveFixtureScores] upserts every row for the
/// fixture in ONE batched statement (`unnest` + `ON CONFLICT (fixture_id,
/// participant_id) DO UPDATE`) — re-scoring the same fixture replaces each
/// participant's row in place, mirroring [PostgresScoreRepository]'s
/// round-level upsert.
///
/// All queries bind values through `@named` parameters (Security ADR §2).
final class PostgresFixtureScoreRepository implements FixtureScoreRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixtureScoreRepository(this._connection);

  final PostgresConnection _connection;

  // --------------------------------------------------------------------------
  // saveFixtureScores — batched, idempotent upsert
  // --------------------------------------------------------------------------

  static const String _upsertSql = '''
INSERT INTO scoring.fixture_scores
  (fixture_id, participant_id, ruleset_version, grade, points, scored_at)
SELECT fixture_id, participant_id, ruleset_version, grade, points, now()
FROM unnest(
  @fixture_ids::uuid[],
  @participant_ids::uuid[],
  @ruleset_versions::int[],
  @grades::text[],
  @points::int[]
) AS t(fixture_id, participant_id, ruleset_version, grade, points)
ON CONFLICT (fixture_id, participant_id) DO UPDATE SET
  ruleset_version = EXCLUDED.ruleset_version,
  grade           = EXCLUDED.grade,
  points          = EXCLUDED.points,
  scored_at       = EXCLUDED.scored_at
''';

  @override
  Future<Result<void>> saveFixtureScores(
    List<ParticipantFixtureScore> scores,
  ) async {
    if (scores.isEmpty) {
      return const Result.ok(null);
    }

    final fixtureIds = <String>[];
    final participantIds = <String>[];
    final rulesetVersions = <int>[];
    final grades = <String>[];
    final points = <int>[];

    for (final score in scores) {
      fixtureIds.add(score.fixture.value);
      participantIds.add(score.participantId.value);
      rulesetVersions.add(score.rulesetVersion);
      grades.add(score.result.grade.wireValue);
      points.add(score.points);
    }

    final result = await _connection.query(
      _upsertSql,
      parameters: {
        'fixture_ids': fixtureIds,
        'participant_ids': participantIds,
        'ruleset_versions': rulesetVersions,
        'grades': grades,
        'points': points,
      },
    );
    return _asVoid(result);
  }

  // --------------------------------------------------------------------------
  // listByFixture — every participant's score for a fixture, id-ordered
  // --------------------------------------------------------------------------

  static const String _selectByFixtureSql = '''
SELECT fixture_id, participant_id, ruleset_version, grade, points
FROM scoring.fixture_scores
WHERE fixture_id = @fixture_id
ORDER BY participant_id ASC
''';

  @override
  Future<Result<List<ParticipantFixtureScore>>> listByFixture(
    FixtureRef fixture,
  ) async {
    final result = await _connection.query(
      _selectByFixtureSql,
      parameters: {'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapList(value),
    };
  }

  Result<List<ParticipantFixtureScore>> _mapList(
    List<Map<String, dynamic>> rows,
  ) {
    final scores = <ParticipantFixtureScore>[];
    for (final row in rows) {
      final mapped = _mapOne(row);
      if (mapped is Err<ParticipantFixtureScore>) {
        return Result.err(mapped.error);
      }
      scores.add((mapped as Ok<ParticipantFixtureScore>).value);
    }
    return Result.ok(List<ParticipantFixtureScore>.unmodifiable(scores));
  }

  Result<ParticipantFixtureScore> _mapOne(Map<String, dynamic> row) {
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final participantIdResult = ParticipantId.tryParse(
      row['participant_id']?.toString(),
    );
    final rulesetVersion = row['ruleset_version'];
    final gradeResult = FixtureScoreGrade.tryParse(row['grade']?.toString());
    final points = row['points'];

    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(
        _corrupt('fixture_scores', 'fixture_id', fixtureResult.error.message),
      );
    }
    if (participantIdResult is Err<ParticipantId>) {
      return Result.err(
        _corrupt(
          'fixture_scores',
          'participant_id',
          participantIdResult.error.message,
        ),
      );
    }
    if (rulesetVersion is! int) {
      return Result.err(
        _corrupt('fixture_scores', 'ruleset_version', 'not an integer'),
      );
    }
    if (gradeResult is Err<FixtureScoreGrade>) {
      return Result.err(
        _corrupt('fixture_scores', 'grade', gradeResult.error.message),
      );
    }
    if (points is! int) {
      return Result.err(_corrupt('fixture_scores', 'points', 'not an integer'));
    }

    final fixture = (fixtureResult as Ok<FixtureRef>).value;
    return ParticipantFixtureScore.fromGraded(
      fixture: fixture,
      participantId: (participantIdResult as Ok<ParticipantId>).value,
      rulesetVersion: rulesetVersion,
      result: FixtureScoreResult(
        fixture: fixture,
        grade: (gradeResult as Ok<FixtureScoreGrade>).value,
        points: points,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Shared helpers (mirror PostgresScoreRepository)
  // --------------------------------------------------------------------------

  Result<void> _asVoid(Result<List<Map<String, dynamic>>> result) {
    return switch (result) {
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
    };
  }

  AppError _reclassify(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException) {
      return error;
    }
    final code = cause.code;
    const integrityCodes = {'23505', '23503', '23514'};
    if (code == null || !integrityCodes.contains(code)) {
      return error;
    }
    final constraint = cause.constraintName;
    if (constraint == 'fixture_scores_participant_id_fkey') {
      return const AppError.invariant(
        'scoring.not_a_participant',
        'Participant not found',
      );
    }
    return const AppError.invariant(
      'scoring.integrity_violation',
      'The write violated a fixture-score integrity rule',
    );
  }

  static AppError _corrupt(String table, String field, String detail) =>
      AppError.transient(
        'scoring.row_corrupt',
        'Stored $table row has invalid $field: $detail',
      );
}
