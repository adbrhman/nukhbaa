import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [NotificationPreferenceRepository] (migration 0063).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter, and speaks only in application types.
final class PostgresNotificationPreferenceRepository
    implements NotificationPreferenceRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresNotificationPreferenceRepository(this._connection);

  final PostgresConnection _connection;

  static const String _readSql = '''
SELECT np.prediction_reminder AS prediction_reminder
FROM notification.notification_preferences np
WHERE np.user_id = @user_id
''';

  // The row is created on the first change; after that the same statement
  // updates it. RETURNING answers with what is stored, not what was sent.
  static const String _saveSql = '''
INSERT INTO notification.notification_preferences
  (user_id, prediction_reminder)
VALUES (@user_id, @prediction_reminder)
ON CONFLICT (user_id) DO UPDATE
  SET prediction_reminder = EXCLUDED.prediction_reminder
RETURNING prediction_reminder
''';

  static const String _reminderOptOutsSql = '''
SELECT np.user_id::text AS user_id
FROM notification.notification_preferences np
WHERE np.prediction_reminder = false
''';

  @override
  Future<Result<NotificationPreferences>> preferencesOf(UserId userId) async {
    final result = await _connection.query(
      _readSql,
      parameters: {'user_id': userId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.ok(NotificationPreferences.defaults)
            : _preferences(value.first),
    };
  }

  @override
  Future<Result<NotificationPreferences>> save(
    UserId userId,
    NotificationPreferences preferences,
  ) async {
    final result = await _connection.query(
      _saveSql,
      parameters: {
        'user_id': userId.value,
        'prediction_reminder': preferences.predictionReminder,
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.err(
                AppError.transient(
                  'notification_preferences.row_corrupt',
                  'the preference upsert returned no row',
                ),
              )
            : _preferences(value.first),
    };
  }

  @override
  Future<Result<Set<String>>> predictionReminderOptOuts() async {
    final result = await _connection.query(_reminderOptOutsSql);
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => _userIds(value),
    };
  }

  static Result<NotificationPreferences> _preferences(
    Map<String, dynamic> row,
  ) {
    final raw = row['prediction_reminder'];
    if (raw is! bool) {
      return const Result.err(
        AppError.transient(
          'notification_preferences.row_corrupt',
          'prediction_reminder was not a boolean',
        ),
      );
    }
    return Result.ok(NotificationPreferences(predictionReminder: raw));
  }

  static Result<Set<String>> _userIds(List<Map<String, dynamic>> rows) {
    final ids = <String>{};
    for (final row in rows) {
      final raw = row['user_id'];
      if (raw is! String) {
        return const Result.err(
          AppError.transient(
            'notification_preferences.row_corrupt',
            'an opted-out row had no user id',
          ),
        );
      }
      ids.add(raw);
    }
    return Result.ok(ids);
  }
}
