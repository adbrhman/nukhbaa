import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_prediction_reminder_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _userB = 'bbbbbbbb-0000-0000-0000-000000000002';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
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

Future<Result<List<ReminderTarget>>> _pending(_FakeConnection connection) =>
    PostgresPredictionReminderRepository(connection).pendingTargets(
      windowStart: DateTime.utc(2026, 9, 22, 21),
      windowEnd: DateTime.utc(2026, 9, 23, 21),
      reminderDate: '2026-09-23',
    );

/// Hermetic unit tests for the row mapping of
/// [PostgresPredictionReminderRepository.pendingTargets]: one row per
/// (user, token), grouped into one target per user carrying the clock the
/// user last reported (P3-2). Which users are due is SQL, checked by hand
/// against the live database.
void main() {
  group('pendingTargets', () {
    test('groups tokens per user and carries each user clock', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'user_id': _userA, 'token': 't1', 'utc_offset_minutes': 180},
          {'user_id': _userA, 'token': 't2', 'utc_offset_minutes': 180},
          {'user_id': _userB, 'token': 't3', 'utc_offset_minutes': null},
        ]),
      );

      final result = await _pending(connection);

      final targets = (result as Ok<List<ReminderTarget>>).value;
      expect(targets, hasLength(2));
      expect(targets[0].userId.value, _userA);
      expect(targets[0].tokens, ['t1', 't2']);
      expect(targets[0].utcOffsetMinutes, 180);
      expect(targets[1].userId.value, _userB);
      expect(targets[1].tokens, ['t3']);
      expect(targets[1].utcOffsetMinutes, isNull);
      expect(connection.sqls.single, contains('u.utc_offset_minutes'));
    });

    test('a non-integer clock is transient, not a guess', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {'user_id': _userA, 'token': 't1', 'utc_offset_minutes': '180'},
        ]),
      );

      final result = await _pending(connection);

      expect(
        (result as Err<List<ReminderTarget>>).error.kind,
        ErrorKind.transient,
      );
    });
  });
}
