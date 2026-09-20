import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [ExperimentRepository] (migration 0054).
///
/// Total (Application ADR §2): never throws, binds every value through a
/// `@named` parameter, and speaks only in domain types.
final class PostgresExperimentRepository implements ExperimentRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresExperimentRepository(this._connection);

  final PostgresConnection _connection;

  static const String _flagSql = '''
SELECT enabled
FROM gamification.feature_flags
WHERE flag_key = @flag_key
''';

  static const String _assignmentSql = '''
SELECT variant
FROM gamification.experiment_assignments
WHERE user_id = @user_id AND flag_key = @flag_key
''';

  // One statement, so a race cannot end with two arms for one user: the
  // insert either wins and returns its own variant, or does nothing and the
  // second branch reads the variant that won. ON CONFLICT DO NOTHING is what
  // makes the loser read instead of raising 23505.
  static const String _assignSql = '''
WITH inserted AS (
  INSERT INTO gamification.experiment_assignments (user_id, flag_key, variant)
  VALUES (@user_id, @flag_key, @variant)
  ON CONFLICT ON CONSTRAINT experiment_assignments_pkey DO NOTHING
  RETURNING variant
)
SELECT variant FROM inserted
UNION ALL
SELECT variant FROM gamification.experiment_assignments
WHERE user_id = @user_id AND flag_key = @flag_key
LIMIT 1
''';

  @override
  Future<Result<bool>> isFlagEnabled(String flagKey) async {
    final result = await _connection.query(
      _flagSql,
      parameters: {'flag_key': flagKey},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      // A flag nobody created is a flag nobody switched on.
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isNotEmpty && (value.first['enabled'] as bool? ?? false),
      ),
    };
  }

  @override
  Future<Result<String?>> readAssignment({
    required UserId userId,
    required String flagKey,
  }) async {
    final result = await _connection.query(
      _assignmentSql,
      parameters: {'user_id': userId.value, 'flag_key': flagKey},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty ? null : value.first['variant'] as String?,
      ),
    };
  }

  @override
  Future<Result<String>> assign({
    required UserId userId,
    required String flagKey,
    required String variant,
  }) async {
    final result = await _connection.query(
      _assignSql,
      parameters: {
        'user_id': userId.value,
        'flag_key': flagKey,
        'variant': variant,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? Result<String>.err(
                const AppError(
                  kind: ErrorKind.transient,
                  code: 'experiment.assignment_not_stored',
                  message: 'The assignment was neither inserted nor found.',
                ),
              )
            : Result<String>.ok(value.first['variant'] as String),
    };
  }
}
