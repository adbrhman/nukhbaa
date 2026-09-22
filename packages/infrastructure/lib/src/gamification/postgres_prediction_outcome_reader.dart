import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [PredictionOutcomeReader] (migrations 0019, 0024, 0027,
/// 0065).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter, and speaks only in domain types.
final class PostgresPredictionOutcomeReader implements PredictionOutcomeReader {
  /// Creates the reader over an open [PostgresConnection].
  const PostgresPredictionOutcomeReader(this._connection);

  final PostgresConnection _connection;

  // One row per fixture: a user in two seasons that share a fixture scored
  // it twice, and DISTINCT ON keeps the better of the two.
  static const String _outcomesSql = '''
SELECT DISTINCT ON (fs.fixture_id)
       fs.fixture_id::text AS fixture_id,
       sch.kickoff_at AS kickoff_at,
       sch.home_team AS home_team,
       sch.away_team AS away_team,
       l.name AS league_name,
       fs.grade AS grade,
       fs.points AS points,
       EXISTS (
         SELECT 1
         FROM identity.user_favorite_teams uft
         WHERE uft.user_id = p.user_id
           AND uft.team_id IN (sch.home_team_id, sch.away_team_id)
       ) AS followed
FROM scoring.fixture_scores fs
JOIN competition.participants p ON p.id = fs.participant_id
JOIN competition.fixture_schedules sch ON sch.fixture_id = fs.fixture_id
LEFT JOIN football_data.leagues l ON l.id = sch.league_id
WHERE p.user_id = @user_id
  AND fs.grade <> 'pending'
  AND sch.kickoff_at >= @from
  AND sch.kickoff_at < @to
ORDER BY fs.fixture_id, fs.points DESC
''';

  static const String _communitySql = '''
SELECT COUNT(*)::int AS decided,
       COUNT(*) FILTER (
         WHERE fs.grade IN ('exact_scoreline', 'correct_outcome')
       )::int AS correct,
       COUNT(*) FILTER (WHERE fs.grade = 'exact_scoreline')::int AS exact
FROM scoring.fixture_scores fs
JOIN competition.fixture_schedules sch ON sch.fixture_id = fs.fixture_id
WHERE fs.grade <> 'pending'
  AND sch.kickoff_at >= @from
  AND sch.kickoff_at < @to
''';

  static const AppError _corrupt = AppError.transient(
    'insights.row_corrupt',
    'a prediction outcome row had unexpected column types',
  );

  @override
  Future<Result<List<PredictionOutcome>>> outcomesOf({
    required UserId userId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _connection.query(
      _outcomesSql,
      parameters: {
        'user_id': userId.value,
        'from': from.toUtc(),
        'to': to.toUtc(),
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final outcomes = <PredictionOutcome>[];
    for (final row in (result as Ok<List<Map<String, dynamic>>>).value) {
      final fixtureId = row['fixture_id'];
      final kickoff = row['kickoff_at'];
      final home = row['home_team'];
      final away = row['away_team'];
      final league = row['league_name'];
      final grade = _grade(row['grade']);
      final points = row['points'];
      final followed = row['followed'];
      if (fixtureId is! String ||
          kickoff is! DateTime ||
          home is! String ||
          away is! String ||
          (league != null && league is! String) ||
          grade == null ||
          points is! int ||
          followed is! bool) {
        return const Result.err(_corrupt);
      }
      outcomes.add(
        PredictionOutcome(
          fixtureId: fixtureId,
          kickoffAt: kickoff.toUtc(),
          homeTeam: home,
          awayTeam: away,
          grade: grade,
          points: points,
          followed: followed,
          leagueName: league is String ? league : null,
        ),
      );
    }
    return Result.ok(outcomes);
  }

  @override
  Future<Result<AccuracyTally>> communityTally({
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _connection.query(
      _communitySql,
      parameters: {'from': from.toUtc(), 'to': to.toUtc()},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(AccuracyTally.empty);
    }
    final decided = rows.first['decided'];
    final correct = rows.first['correct'];
    final exact = rows.first['exact'];
    if (decided is! int || correct is! int || exact is! int) {
      return const Result.err(_corrupt);
    }
    return Result.ok(
      AccuracyTally(decided: decided, correct: correct, exact: exact),
    );
  }

  static PredictionGrade? _grade(Object? raw) => switch (raw) {
    'exact_scoreline' => PredictionGrade.exact,
    'correct_outcome' => PredictionGrade.correct,
    'incorrect' => PredictionGrade.incorrect,
    _ => null,
  };
}
