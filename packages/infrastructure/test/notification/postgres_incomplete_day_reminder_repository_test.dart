import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_incomplete_day_reminder_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _userB = 'bbbbbbbb-0000-0000-0000-000000000002';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
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

/// Hermetic unit tests for the row mapping of the incomplete-day adapter.
/// Which players are due is SQL, checked against a seeded Postgres 16
/// before batch 117.
void main() {
  group('PostgresIncompleteDayReminderRepository.dueTargets', () {
    test('folds devices into one target per player, in order', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {
            'user_id': _userA,
            'remaining': 3,
            'token': 't1',
            'utc_offset_minutes': null,
            'prediction_reminder': true,
          },
          {
            'user_id': _userA,
            'remaining': 3,
            'token': 't2',
            'utc_offset_minutes': null,
            'prediction_reminder': true,
          },
          {
            'user_id': _userB,
            'remaining': 1,
            'token': 't3',
            'utc_offset_minutes': 180,
            'prediction_reminder': false,
          },
        ]),
      );

      final result = await PostgresIncompleteDayReminderRepository(connection)
          .dueTargets(
            today: '2026-09-15',
            now: DateTime.utc(2026, 9, 15, 12),
            from: DateTime.utc(2026, 9, 15, 13, 15),
            to: DateTime.utc(2026, 9, 15, 13, 45),
          );

      final targets = (result as Ok<List<IncompleteDayTarget>>).value;
      expect(targets, hasLength(2));
      expect(targets.first.userId.value, _userA);
      expect(targets.first.tokens, ['t1', 't2']);
      expect(targets.first.remaining, 3);
      expect(targets.first.optedIn, isTrue);
      expect(targets.first.utcOffsetMinutes, isNull);
      expect(targets.last.remaining, 1);
      expect(targets.last.optedIn, isFalse);
      expect(targets.last.utcOffsetMinutes, 180);
      expect(connection.params.single['today'], '2026-09-15');
      expect(connection.params.single['now'], DateTime.utc(2026, 9, 15, 12));
    });

    test('a row of unexpected types is a transient error', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {
            'user_id': _userA,
            'remaining': '3',
            'token': 't1',
            'utc_offset_minutes': null,
            'prediction_reminder': true,
          },
        ]),
      );

      final result = await PostgresIncompleteDayReminderRepository(connection)
          .dueTargets(
            today: '2026-09-15',
            now: DateTime.utc(2026, 9, 15, 12),
            from: DateTime.utc(2026, 9, 15, 13, 15),
            to: DateTime.utc(2026, 9, 15, 13, 45),
          );

      expect(
        (result as Err<List<IncompleteDayTarget>>).error.code,
        'incomplete_day.row_corrupt',
      );
    });
  });

  group('PostgresIncompleteDayReminderRepository.markSent', () {
    test('records the player and the Riyadh day', () async {
      final connection = _FakeConnection(const Result.ok([]));

      final result = await PostgresIncompleteDayReminderRepository(connection)
          .markSent(
            userId: (UserId.tryParse(_userA) as Ok<UserId>).value,
            sendDate: '2026-09-15',
            now: DateTime.utc(2026, 9, 15, 12),
          );

      expect(result, isA<Ok<void>>());
      expect(connection.sqls.single, contains('incomplete_day_sends'));
      expect(connection.params.single['user_id'], _userA);
      expect(connection.params.single['send_date'], '2026-09-15');
    });
  });
}
