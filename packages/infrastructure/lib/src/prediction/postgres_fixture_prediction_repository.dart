import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
// `postgres` exports its own `Result`; only its exception hierarchy is
// needed here (to read the SQLSTATE `code`/`constraintName` off a
// `ServerException`), so hide `Result` to keep `Result<T>` unambiguously
// our `shared` union — mirrors PostgresPredictionRepository.
import 'package:postgres/postgres.dart' hide Result;
import 'package:shared/shared.dart';

/// Postgres-backed [FixturePredictionRepository] over
/// `prediction.fixture_predictions` (Axiom 4 Amendment; migration
/// `0019_axiom4_fixture_prediction_scoring.sql`) plus read-only projections of
/// `competition.season_fixtures` and `competition.fixture_schedules`, both
/// owned by earlier migrations.
///
/// The per-fixture sibling of [PostgresPredictionRepository] — same shape,
/// one row per (participant, fixture) instead of a parent + N child scores,
/// because a fixture prediction is a single scoreline.
///
/// Error mapping mirrors [PostgresPredictionRepository]:
/// * `fixture_predictions_participant_fixture_uniq` (`23505`) →
///   [ErrorKind.invariant] `prediction.already_submitted`.
/// * `fixture_predictions_participant_id_fkey` (`23503`) →
///   `prediction.not_a_participant`.
/// * A check/trigger rejection (`23514`, the "no write after kickoff"
///   backstop or a goal-range check) → `prediction.fixture_locked`.
/// * A genuinely transient/infrastructure failure stays [ErrorKind.transient].
///
/// All queries bind values through `@named` parameters (Security ADR §2).
final class PostgresFixturePredictionRepository
    implements FixturePredictionRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresFixturePredictionRepository(this._connection);

  final PostgresConnection _connection;

  // --------------------------------------------------------------------------
  // findByFixtureAndParticipant
  // --------------------------------------------------------------------------

  static const String _selectByFixtureAndParticipantSql = '''
SELECT id, fixture_id, participant_id, home_goals, away_goals, is_double,
       submitted_at
FROM prediction.fixture_predictions
WHERE fixture_id = @fixture_id AND participant_id = @participant_id
''';

  @override
  Future<Result<FixturePredictionView?>> findByFixtureAndParticipant(
    FixtureRef fixture,
    ParticipantId participantId,
  ) async {
    final result = await _connection.query(
      _selectByFixtureAndParticipantSql,
      parameters: {
        'fixture_id': fixture.value,
        'participant_id': participantId.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      // Absence is a normal, successful "not yet predicted" outcome, exactly
      // like PostgresPredictionRepository.findByRoundAndParticipant.
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapOne(value.first),
    };
  }

  Result<FixturePredictionView?> _mapOne(Map<String, dynamic> row) {
    final idResult = PredictionId.tryParse(row['id']?.toString());
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final participantIdResult = ParticipantId.tryParse(
      row['participant_id']?.toString(),
    );
    final homeGoals = row['home_goals'];
    final awayGoals = row['away_goals'];
    final isDouble = row['is_double'];

    if (idResult is Err<PredictionId>) {
      return Result.err(
        _corrupt('fixture_predictions', 'id', idResult.error.message),
      );
    }
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(
        _corrupt(
          'fixture_predictions',
          'fixture_id',
          fixtureResult.error.message,
        ),
      );
    }
    if (participantIdResult is Err<ParticipantId>) {
      return Result.err(
        _corrupt(
          'fixture_predictions',
          'participant_id',
          participantIdResult.error.message,
        ),
      );
    }
    if (homeGoals is! int) {
      return Result.err(
        _corrupt('fixture_predictions', 'home_goals', 'not an integer'),
      );
    }
    if (awayGoals is! int) {
      return Result.err(
        _corrupt('fixture_predictions', 'away_goals', 'not an integer'),
      );
    }
    if (isDouble is! bool) {
      return Result.err(
        _corrupt('fixture_predictions', 'is_double', 'not a boolean'),
      );
    }
    final submittedAtResult = _timestampOf(row, 'submitted_at');
    if (submittedAtResult is Err<DateTime>) {
      return Result.err(submittedAtResult.error);
    }

    final predictionResult = FixturePrediction.fromStored(
      id: (idResult as Ok<PredictionId>).value,
      fixture: (fixtureResult as Ok<FixtureRef>).value,
      participantId: (participantIdResult as Ok<ParticipantId>).value,
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      isDouble: isDouble,
    );

    return Result.ok(
      FixturePredictionView(
        prediction: predictionResult,
        submittedAt: (submittedAtResult as Ok<DateTime>).value,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // save / update
  // --------------------------------------------------------------------------

  static const String _insertSql = '''
INSERT INTO prediction.fixture_predictions
  (id, fixture_id, participant_id, home_goals, away_goals, is_double,
   submitted_at)
VALUES (@id, @fixture_id, @participant_id, @home_goals, @away_goals,
        @is_double, @submitted_at)
''';

  @override
  Future<Result<void>> save(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final result = await _connection.query(
      _insertSql,
      parameters: {
        'id': prediction.id.value,
        'fixture_id': prediction.fixture.value,
        'participant_id': prediction.participantId.value,
        'home_goals': prediction.homeGoals,
        'away_goals': prediction.awayGoals,
        'is_double': prediction.isDouble,
        'submitted_at': submittedAt.toUtc().toIso8601String(),
      },
    );
    return _asVoid(result);
  }

  // Guarded on identity via RETURNING, exactly like
  // PostgresPredictionRepository.update: zero rows means the prediction no
  // longer exists (deleted between the use-case's read and this write).
  static const String _updateSql = '''
UPDATE prediction.fixture_predictions
SET home_goals = @home_goals,
    away_goals = @away_goals,
    is_double  = @is_double,
    submitted_at = @submitted_at
WHERE id = @id
RETURNING id
''';

  @override
  Future<Result<void>> update(
    FixturePrediction prediction,
    DateTime submittedAt,
  ) async {
    final result = await _connection.query(
      _updateSql,
      parameters: {
        'id': prediction.id.value,
        'home_goals': prediction.homeGoals,
        'away_goals': prediction.awayGoals,
        'is_double': prediction.isDouble,
        'submitted_at': submittedAt.toUtc().toIso8601String(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(
        _reclassify(error),
      ),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.err(
                AppError.invariant(
                  'prediction.not_found',
                  'Prediction no longer exists',
                ),
              )
            : const Result.ok(null),
    };
  }

  // --------------------------------------------------------------------------
  // findSeasonFixture — read-only projection of competition.season_fixtures
  // --------------------------------------------------------------------------

  static const String _selectSeasonFixtureSql = '''
SELECT season_id, fixture_id, display_order
FROM competition.season_fixtures
WHERE season_id = @season_id AND fixture_id = @fixture_id
''';

  @override
  Future<Result<SeasonFixture?>> findSeasonFixture(
    SeasonId seasonId,
    FixtureRef fixture,
  ) async {
    final result = await _connection.query(
      _selectSeasonFixtureSql,
      parameters: {'season_id': seasonId.value, 'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty ? const Result.ok(null) : _mapSeasonFixture(value.first),
    };
  }

  Result<SeasonFixture?> _mapSeasonFixture(Map<String, dynamic> row) {
    final seasonIdResult = SeasonId.tryParse(row['season_id']?.toString());
    final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
    final displayOrder = row['display_order'];

    if (seasonIdResult is Err<SeasonId>) {
      return Result.err(
        _corrupt('season_fixtures', 'season_id', seasonIdResult.error.message),
      );
    }
    if (fixtureResult is Err<FixtureRef>) {
      return Result.err(
        _corrupt('season_fixtures', 'fixture_id', fixtureResult.error.message),
      );
    }
    if (displayOrder is! int) {
      return Result.err(
        _corrupt('season_fixtures', 'display_order', 'not an integer'),
      );
    }

    return Result.ok(
      SeasonFixture.fromStored(
        seasonId: (seasonIdResult as Ok<SeasonId>).value,
        fixture: (fixtureResult as Ok<FixtureRef>).value,
        displayOrder: displayOrder,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // countDoublesOnDay
  //
  // Joins fixture_predictions -> competition.fixture_schedules to group
  // stored doubles by the UTC calendar day of their fixture's kickoff — a
  // fixture_prediction whose fixture has NO schedule row is excluded (it
  // cannot be attributed to any day), matching the "no schedule = not
  // locked" default the use-case applies on the write side.
  // --------------------------------------------------------------------------

  static const String _countDoublesSql = '''
SELECT count(*) AS n
FROM prediction.fixture_predictions fp
JOIN competition.fixture_schedules fs ON fs.fixture_id = fp.fixture_id
WHERE fp.participant_id = @participant_id
  AND fp.is_double = true
  AND fs.kickoff_at >= @day_start AND fs.kickoff_at < @day_end
  AND (@excluding_fixture_id::uuid IS NULL
       OR fp.fixture_id <> @excluding_fixture_id)
''';

  @override
  Future<Result<int>> countDoublesOnDay(
    ParticipantId participantId,
    DateTime dayUtc, {
    FixtureRef? excludingFixture,
  }) async {
    final dayStart = DateTime.utc(dayUtc.year, dayUtc.month, dayUtc.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final result = await _connection.query(
      _countDoublesSql,
      parameters: {
        'participant_id': participantId.value,
        'day_start': dayStart.toIso8601String(),
        'day_end': dayEnd.toIso8601String(),
        'excluding_fixture_id': excludingFixture?.value,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapCount(value),
    };
  }

  Result<int> _mapCount(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Result.ok(0);
    }
    final raw = rows.first['n'];
    if (raw is int) {
      return Result.ok(raw);
    }
    // The `postgres` driver may return count(*) as a BigInt-backed int; a
    // defensive numeric-string fallback covers a text-codec projection.
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null) {
      return Result.ok(parsed);
    }
    return Result.err(_corrupt('fixture_predictions', 'count', 'not a count'));
  }

  // --------------------------------------------------------------------------
  // listByFixture — every participant's prediction for a fixture
  // --------------------------------------------------------------------------

  static const String _selectByFixtureSql = '''
SELECT id, fixture_id, participant_id, home_goals, away_goals, is_double,
       submitted_at
FROM prediction.fixture_predictions
WHERE fixture_id = @fixture_id
ORDER BY submitted_at ASC, id ASC
''';

  @override
  Future<Result<List<FixturePredictionView>>> listByFixture(
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

  Result<List<FixturePredictionView>> _mapList(
    List<Map<String, dynamic>> rows,
  ) {
    final views = <FixturePredictionView>[];
    for (final row in rows) {
      final mapped = _mapOne(row);
      if (mapped is Err<FixturePredictionView?>) {
        return Result.err(mapped.error);
      }
      final view = (mapped as Ok<FixturePredictionView?>).value;
      if (view != null) {
        views.add(view);
      }
    }
    return Result.ok(List<FixturePredictionView>.unmodifiable(views));
  }

  // --------------------------------------------------------------------------
  // Shared helpers (mirror PostgresPredictionRepository)
  // --------------------------------------------------------------------------

  Result<DateTime> _timestampOf(Map<String, dynamic> row, String column) {
    final raw = row[column];
    if (raw is DateTime) {
      return Result.ok(raw.toUtc());
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return Result.ok(parsed.toUtc());
      }
    }
    return Result.err(
      _corrupt('fixture_predictions', column, 'not a timestamp'),
    );
  }

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
    switch (constraint) {
      case 'fixture_predictions_participant_fixture_uniq':
        return const AppError.invariant(
          'prediction.already_submitted',
          'A prediction already exists for this participant and fixture',
        );
      case 'fixture_predictions_pkey':
        return const AppError.invariant(
          'prediction.duplicate_id',
          'A prediction with this id already exists',
        );
      case 'fixture_predictions_participant_id_fkey':
        return const AppError.invariant(
          'prediction.not_a_participant',
          'Participant not found',
        );
    }

    // The trigger-raised "no write after kickoff" check_violation carries no
    // constraint name — same pattern as prediction.round_not_open.
    if (code == '23514') {
      return const AppError.invariant(
        'prediction.fixture_locked',
        'Predictions can only be written before the fixture kicks off',
      );
    }
    return const AppError.invariant(
      'prediction.integrity_violation',
      'The write violated a fixture-prediction integrity rule',
    );
  }

  static AppError _corrupt(String table, String field, String detail) =>
      AppError.transient(
        'prediction.row_corrupt',
        'Stored $table row has invalid $field: $detail',
      );

  // --------------------------------------------------------------------------
  // listSeasonFixtures — every fixture linked to a season, display-ordered
  // --------------------------------------------------------------------------

  static const String _selectSeasonFixturesSql = '''
SELECT fixture_id
FROM competition.season_fixtures
WHERE season_id = @season_id
ORDER BY display_order ASC
''';

  @override
  Future<Result<List<FixtureRef>>> listSeasonFixtures(SeasonId seasonId) async {
    final result = await _connection.query(
      _selectSeasonFixturesSql,
      parameters: {'season_id': seasonId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapFixtureRefs(value),
    };
  }

  Result<List<FixtureRef>> _mapFixtureRefs(List<Map<String, dynamic>> rows) {
    final refs = <FixtureRef>[];
    for (final row in rows) {
      final fixtureResult = FixtureRef.tryParse(row['fixture_id']?.toString());
      if (fixtureResult is Err<FixtureRef>) {
        return Result.err(
          AppError.transient(
            'competition.row_corrupt',
            'Stored season_fixtures row has invalid fixture_id: '
                '${fixtureResult.error.message}',
          ),
        );
      }
      refs.add((fixtureResult as Ok<FixtureRef>).value);
    }
    return Result.ok(List<FixtureRef>.unmodifiable(refs));
  }
}
