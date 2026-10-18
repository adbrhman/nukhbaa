import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/notification/postgres_push_open_repository.dart';
import 'package:infrastructure/src/notification/postgres_streak_saver_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userA = 'aaaaaaaa-0000-0000-0000-000000000001';
const _fixture = '11111111-1111-4111-8111-111111111111';

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

/// Hermetic unit tests for the row mapping of the streak-saver and
/// push-open adapters. Which users are due is SQL, checked by hand against
/// the live database.
void main() {
  group('PostgresStreakSaverRepository.dueTargets', () {
    test('folds devices into one target per user', () async {
      final connection = _FakeConnection(
        const Result.ok([
          {
            'user_id': _userA,
            'fixture_id': _fixture,
            'token': 't1',
            'utc_offset_minutes': null,
            'streak_saver': true,
          },
          {
            'user_id': _userA,
            'fixture_id': _fixture,
            'token': 't2',
            'utc_offset_minutes': null,
            'streak_saver': true,
          },
        ]),
      );

      final result = await PostgresStreakSaverRepository(connection).dueTargets(
        today: '2026-09-15',
        from: DateTime.utc(2026, 9, 15, 12, 45),
        to: DateTime.utc(2026, 9, 15, 13, 15),
      );

      final targets = (result as Ok<List<StreakSaverTarget>>).value;
      expect(targets.single.tokens, ['t1', 't2']);
      expect(targets.single.optedIn, isTrue);
      expect(connection.params.single['today'], '2026-09-15');
    });
  });

  test('PostgresPushOpenRepository records the tap', () async {
    final connection = _FakeConnection(const Result.ok([]));
    final at = DateTime.utc(2026, 9, 23, 12);

    final result = await PostgresPushOpenRepository(
      connection,
    ).record(userId: const UserId(_userA), link: 'league', openedAt: at);

    expect(result.isOk, isTrue);
    expect(connection.params.single, {
      'user_id': _userA,
      'link': 'league',
      'opened_at': at,
    });
    expect(connection.sqls.single, contains('notification.push_opens'));
  });
}
