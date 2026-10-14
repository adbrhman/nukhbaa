import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_weekly_league_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _leagueId = '11111111-1111-4111-8111-111111111111';
const _newLeagueId = '22222222-2222-4222-8222-222222222222';
const _userId = '33333333-3333-4333-8333-333333333333';

/// Answers each statement in turn and records what was asked.
final class _ScriptedConnection implements PostgresConnection {
  _ScriptedConnection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sql = <String>[];
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String statement, {
    Map<String, Object?> parameters = const {},
  }) async {
    sql.add(statement);
    this.parameters.add(parameters);
    return _answers[sql.length - 1];
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) => action(this);

  @override
  Future<void> close() async {}
}

Future<Result<WeeklyLeagueSeat>> _place(_ScriptedConnection connection) =>
    PostgresWeeklyLeagueRepository(connection).place(
      userId: const UserId(_userId),
      weekStart: DateTime.utc(2026, 10, 12),
      tier: WeeklyLeagueTier.silver,
      newLeagueId: const WeeklyLeagueId(_newLeagueId),
      capacity: 30,
    );

void main() {
  test('a placement first locks its week and tier (audit L-45)', () async {
    final connection = _ScriptedConnection([
      const Result.ok([{}]),
      const Result.ok([
        {'league_id': _leagueId, 'tier': 2, 'group_index': 0},
      ]),
      const Result.ok([]),
      Result.ok([
        {
          'league_id': _leagueId,
          'tier': 2,
          'group_index': 0,
          'joined_at': DateTime.utc(2026, 10, 13, 9),
        },
      ]),
    ]);

    final result = await _place(connection);

    expect(result, isA<Ok<WeeklyLeagueSeat>>());
    expect(connection.sql.first, contains('pg_advisory_xact_lock'));
    expect(connection.parameters.first, {
      'week_start': '2026-10-12',
      'tier': '2',
    });
    // The open group is read only once the lock is held.
    expect(connection.sql[1], contains('HAVING count(m.user_id) < l.capacity'));
  });

  test('a failed lock places nobody', () async {
    const failure = AppError.transient('db.query_timeout', 'timed out');
    final connection = _ScriptedConnection([const Result.err(failure)]);

    final result = await _place(connection);

    expect((result as Err<WeeklyLeagueSeat>).error, failure);
    expect(connection.sql, hasLength(1));
  });
}
