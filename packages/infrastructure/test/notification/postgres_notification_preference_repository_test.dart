import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_notification_preference_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-1111-1111-1111-111111111111';

UserId _id(String raw) => (UserId.tryParse(raw) as Ok<UserId>).value;

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
    return _response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async => action(this);

  @override
  Future<void> close() async {}
}

const _failure = Result<List<Map<String, dynamic>>>.err(
  AppError.transient('db.query_failed', 'Database query failed'),
);

/// Hermetic unit tests for [PostgresNotificationPreferenceRepository]: a
/// fake [PostgresConnection] replays scripted rows and records every SQL and
/// parameter set. That the upsert really creates then updates one row is
/// checked by hand against the live database.
void main() {
  group('preferencesOf', () {
    test('no row reads the defaults', () async {
      final connection = _FakeConnection(const Result.ok([]));
      final repository = PostgresNotificationPreferenceRepository(connection);

      final result = await repository.preferencesOf(_id(_user));

      expect(
        (result as Ok<NotificationPreferences>).value,
        NotificationPreferences.defaults,
      );
      expect(connection.parameters.single, {'user_id': _user});
      expect(connection.sqls.single, contains('WHERE np.user_id = @user_id'));
    });

    test('a stored row is read as stored', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'prediction_reminder': false, 'pre_match': false},
        ]),
      );
      final repository = PostgresNotificationPreferenceRepository(connection);

      final result = await repository.preferencesOf(_id(_user));

      expect(
        (result as Ok<NotificationPreferences>).value.predictionReminder,
        isFalse,
      );
      expect(result.value.preMatch, isFalse);
    });

    test('a non-boolean column is transient, not a guess', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'prediction_reminder': 'f'},
        ]),
      );
      final repository = PostgresNotificationPreferenceRepository(connection);

      final result = await repository.preferencesOf(_id(_user));

      expect(
        (result as Err<NotificationPreferences>).error.kind,
        ErrorKind.transient,
      );
    });

    test('a driver failure is passed through', () async {
      final repository = PostgresNotificationPreferenceRepository(
        _FakeConnection(_failure),
      );

      final result = await repository.preferencesOf(_id(_user));

      expect(
        (result as Err<NotificationPreferences>).error.code,
        'db.query_failed',
      );
    });
  });

  group('save', () {
    test('upserts the caller row and answers what was stored', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'prediction_reminder': false, 'pre_match': true},
        ]),
      );
      final repository = PostgresNotificationPreferenceRepository(connection);

      final result = await repository.save(
        _id(_user),
        const NotificationPreferences(predictionReminder: false),
      );

      expect(
        (result as Ok<NotificationPreferences>).value.predictionReminder,
        isFalse,
      );
      expect(connection.parameters.single, {
        'user_id': _user,
        'prediction_reminder': false,
        'pre_match': true,
      });
      expect(connection.sqls.single, contains('ON CONFLICT (user_id)'));
      expect(connection.sqls.single, contains('RETURNING prediction_reminder'));
    });

    test('an upsert that returns no row is transient', () async {
      final repository = PostgresNotificationPreferenceRepository(
        _FakeConnection(const Result.ok([])),
      );

      final result = await repository.save(
        _id(_user),
        NotificationPreferences.defaults,
      );

      expect(
        (result as Err<NotificationPreferences>).error.kind,
        ErrorKind.transient,
      );
    });
  });

  group('predictionReminderOptOuts', () {
    test('answers the ids of every user who turned the reminder off', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'user_id': _user},
          {'user_id': '22222222-2222-2222-2222-222222222222'},
        ]),
      );
      final repository = PostgresNotificationPreferenceRepository(connection);

      final result = await repository.predictionReminderOptOuts();

      expect((result as Ok<Set<String>>).value, {
        _user,
        '22222222-2222-2222-2222-222222222222',
      });
      expect(
        connection.sqls.single,
        contains('WHERE np.prediction_reminder = false'),
      );
    });

    test('a row without a text id is transient', () async {
      final repository = PostgresNotificationPreferenceRepository(
        _FakeConnection(
          const Result.ok([
            {'user_id': null},
          ]),
        ),
      );

      final result = await repository.predictionReminderOptOuts();

      expect((result as Err<Set<String>>).error.kind, ErrorKind.transient);
    });
  });
}
