import 'package:application/application.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_retention_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

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

/// Hermetic unit tests for the row mapping of the retention adapter. The
/// SQL itself was run by hand against the views of migration 0069.
void main() {
  test('weeks read the 0069 views and bind Riyadh days', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {
          'week_start': '2026-09-21',
          'active_users': 12,
          'active_3plus': 5,
          'league_active': 7,
          'league_active_3plus': 4,
          'league_members': 9,
          'league_returned': 6,
        },
      ]),
    );

    final result = await PostgresRetentionReader(
      connection,
    ).weeks(from: DateTime.utc(2026, 8, 3), through: DateTime.utc(2026, 9, 28));

    final week = (result as Ok<List<WeeklyActivity>>).value.single;
    expect(week.weekStart, DateTime.utc(2026, 9, 21));
    expect(week.activeUsers, 12);
    expect(week.active3Plus, 5);
    expect(week.leagueActive, 7);
    expect(week.leagueActive3Plus, 4);
    expect(week.leagueMembers, 9);
    expect(week.leagueReturned, 6);
    expect(
      connection.sqls.single,
      contains('gamification.kpi_weekly_engagement'),
    );
    expect(
      connection.sqls.single,
      contains('gamification.kpi_league_retention'),
    );
    expect(connection.params.single, {
      'from': '2026-08-03',
      'through': '2026-09-28',
    });
  });

  test('cohorts map every horizon', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {
          'week_start': '2026-09-07',
          'users': 3,
          'day1_eligible': 3,
          'day1': 2,
          'day7_eligible': 3,
          'day7': 1,
          'day14_eligible': 3,
          'day14': 1,
          'week4_eligible': 0,
          'week4': 0,
        },
      ]),
    );

    final result = await PostgresRetentionReader(
      connection,
    ).cohorts(from: DateTime.utc(2026, 9, 7), today: DateTime.utc(2026, 9, 28));

    final cohort = (result as Ok<List<RetentionCohort>>).value.single;
    expect(cohort.weekStart, DateTime.utc(2026, 9, 7));
    expect(cohort.users, 3);
    expect(cohort.day1Eligible, 3);
    expect(cohort.day1, 2);
    expect(cohort.day7, 1);
    expect(cohort.day14Eligible, 3);
    expect(cohort.day14, 1);
    expect(cohort.week4Eligible, 0);
    expect(connection.sqls.single, contains('gamification.user_active_days'));
    expect(connection.params.single, {
      'from': '2026-09-07',
      'today': '2026-09-28',
    });
  });

  test('an unreadable week is refused, not guessed', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'week_start': null, 'active_users': 1},
      ]),
    );

    final result = await PostgresRetentionReader(
      connection,
    ).weeks(from: DateTime.utc(2026, 9, 7), through: DateTime.utc(2026, 9, 28));

    expect(result.isErr, isTrue);
  });

  test('a driver failure passes through', () async {
    final connection = _FakeConnection(
      const Result.err(AppError.transient('db.down', 'down')),
    );

    final result = await PostgresRetentionReader(
      connection,
    ).cohorts(from: DateTime.utc(2026, 9, 7), today: DateTime.utc(2026, 9, 28));

    expect(result.isErr, isTrue);
  });
}
