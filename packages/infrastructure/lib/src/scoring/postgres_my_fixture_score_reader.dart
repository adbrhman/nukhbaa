import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [MyFixtureScoreReader] over `scoring.my_fixture_scores`
/// (migration 0171).
///
/// The rule -- which of the user's predictions have a score or a result --
/// lives in SQL, where the migration's end-to-end test exercises it against
/// real tables; this adapter binds the user id and maps the rows. A grade or
/// points left null are a result still waiting to be scored, not a fault.
final class PostgresMyFixtureScoreReader implements MyFixtureScoreReader {
  /// Creates the reader over the shared [PostgresConnection].
  const PostgresMyFixtureScoreReader(this._connection);

  final PostgresConnection _connection;

  static const String _sql = '''
SELECT participant_id::text AS participant_id,
       fixture_id::text AS fixture_id,
       grade,
       points,
       result_home_goals,
       result_away_goals
FROM scoring.my_fixture_scores(@user_id::uuid)
''';

  @override
  Future<Result<List<MyFixtureScore>>> listByUser(UserId userId) async {
    final result = await _connection.query(
      _sql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _mapList(value),
    };
  }

  static Result<List<MyFixtureScore>> _mapList(
    List<Map<String, dynamic>> rows,
  ) {
    final scores = <MyFixtureScore>[];
    for (final row in rows) {
      final mapped = _mapOne(row);
      if (mapped is Err<MyFixtureScore>) {
        return Result.err(mapped.error);
      }
      scores.add((mapped as Ok<MyFixtureScore>).value);
    }
    return Result.ok(List<MyFixtureScore>.unmodifiable(scores));
  }

  static Result<MyFixtureScore> _mapOne(Map<String, dynamic> row) {
    final participant = ParticipantId.tryParse(
      row['participant_id']?.toString(),
    );
    if (participant is Err<ParticipantId>) {
      return Result.err(_corrupt('participant_id', participant.error.message));
    }
    final fixtureRef = FixtureRef.tryParse(row['fixture_id']?.toString());
    if (fixtureRef is Err<FixtureRef>) {
      return Result.err(_corrupt('fixture_id', fixtureRef.error.message));
    }
    final fixture = (fixtureRef as Ok<FixtureRef>).value;

    final Object? rawGrade = row['grade'];
    FixtureScoreGrade? grade;
    if (rawGrade != null) {
      final parsed = FixtureScoreGrade.tryParse(rawGrade.toString());
      if (parsed is Err<FixtureScoreGrade>) {
        return Result.err(_corrupt('grade', parsed.error.message));
      }
      grade = (parsed as Ok<FixtureScoreGrade>).value;
    }

    final Object? points = row['points'];
    if (points != null && points is! int) {
      return Result.err(_corrupt('points', 'not an integer'));
    }
    if ((grade == null) != (points == null)) {
      return Result.err(_corrupt('grade', 'grade and points come together'));
    }

    final Object? home = row['result_home_goals'];
    final Object? away = row['result_away_goals'];
    FixtureResult? finalScore;
    if (home != null || away != null) {
      if (home is! int || away is! int) {
        return Result.err(
          _corrupt('result', 'both sides of the score are integers'),
        );
      }
      finalScore = FixtureResult.fromStored(
        fixture: fixture,
        homeGoals: home,
        awayGoals: away,
      );
    }

    return Result.ok(
      MyFixtureScore(
        participantId: (participant as Ok<ParticipantId>).value,
        fixture: fixture,
        grade: grade,
        points: points as int?,
        result: finalScore,
      ),
    );
  }

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'scoring.row_corrupt',
    'Stored my_fixture_scores row has invalid $field: $detail',
  );
}
