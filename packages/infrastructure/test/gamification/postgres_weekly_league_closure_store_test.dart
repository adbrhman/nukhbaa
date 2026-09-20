import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_weekly_league_closure_store.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _leagueA = '11111111-1111-1111-1111-111111111111';
const _leagueB = '22222222-2222-2222-2222-222222222222';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;

  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    this.parameters.add(parameters);
    final response =
        _responses[_index < _responses.length ? _index : _responses.length - 1];
    _index++;
    return response;
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

_FakeConnection _rows(List<Map<String, dynamic>> rows) =>
    _FakeConnection([Result.ok(rows)]);

_FakeConnection _fails() => _FakeConnection([
  const Result.err(
    AppError.transient('db.query_failed', 'Database query failed'),
  ),
]);

/// Hermetic unit tests for [PostgresWeeklyLeagueClosureStore]: a fake
/// [PostgresConnection] replays scripted rows and records every SQL and
/// parameter set. What only a real server can prove (that the anti-join
/// finds the oldest unclosed week, that the insert lands) is checked by hand
/// against the live database, with a date outside the live range.
void main() {
  group('PostgresWeeklyLeagueClosureStore.nextUnclosedWeek', () {
    test('maps the projected text day to a UTC Monday', () async {
      final connection = _rows([
        {'week_start': '2026-09-21'},
      ]);

      final result = await PostgresWeeklyLeagueClosureStore(
        connection,
      ).nextUnclosedWeek();

      expect((result as Ok<DateTime?>).value, DateTime.utc(2026, 9, 21));
      final sql = connection.sqls.single;
      expect(sql, contains('gamification.weekly_leagues'));
      expect(sql, contains('gamification.weekly_league_closures'));
    });

    test('reads null when no week is waiting', () async {
      final nullDay = await PostgresWeeklyLeagueClosureStore(
        _rows([
          {'week_start': null},
        ]),
      ).nextUnclosedWeek();
      expect((nullDay as Ok<DateTime?>).value, isNull);

      final noRows = await PostgresWeeklyLeagueClosureStore(
        _rows(const <Map<String, dynamic>>[]),
      ).nextUnclosedWeek();
      expect((noRows as Ok<DateTime?>).value, isNull);
    });

    test('maps an unreadable week to a transient error', () async {
      final result = await PostgresWeeklyLeagueClosureStore(
        _rows([
          {'week_start': 'not-a-date'},
        ]),
      ).nextUnclosedWeek();

      expect((result as Err<DateTime?>).error.code, 'gamification.row_corrupt');
    });

    test('passes a query failure through', () async {
      final result = await PostgresWeeklyLeagueClosureStore(
        _fails(),
      ).nextUnclosedWeek();

      expect((result as Err<DateTime?>).error.code, 'db.query_failed');
    });
  });

  group('PostgresWeeklyLeagueClosureStore.groupsOf', () {
    test('binds the week as an ISO day and maps each group', () async {
      final connection = _rows([
        {'league_id': _leagueA, 'tier': 1},
        {'league_id': _leagueB, 'tier': '2'},
      ]);

      final result = await PostgresWeeklyLeagueClosureStore(
        connection,
      ).groupsOf(DateTime.utc(2026, 9, 7));

      final groups = (result as Ok<List<WeeklyLeagueGroupRef>>).value;
      expect(groups, hasLength(2));
      expect(groups[0].leagueId, const WeeklyLeagueId(_leagueA));
      expect(groups[0].tier, WeeklyLeagueTier.bronze);
      expect(groups[1].leagueId, const WeeklyLeagueId(_leagueB));
      expect(groups[1].tier, WeeklyLeagueTier.silver);
      expect(connection.parameters.single['week_start'], '2026-09-07');
    });

    test('a week with no group is an empty list, not an error', () async {
      final result = await PostgresWeeklyLeagueClosureStore(
        _rows(const <Map<String, dynamic>>[]),
      ).groupsOf(DateTime.utc(2026, 9, 7));

      expect((result as Ok<List<WeeklyLeagueGroupRef>>).value, isEmpty);
    });

    test('an unknown tier is an error, never a skipped group', () async {
      final result = await PostgresWeeklyLeagueClosureStore(
        _rows([
          {'league_id': _leagueA, 'tier': 9},
        ]),
      ).groupsOf(DateTime.utc(2026, 9, 7));

      expect(
        (result as Err<List<WeeklyLeagueGroupRef>>).error.code,
        'gamification.weekly_league_tier_unknown',
      );
    });

    test('a malformed group id is an error', () async {
      final result = await PostgresWeeklyLeagueClosureStore(
        _rows([
          {'league_id': 'nope', 'tier': 1},
        ]),
      ).groupsOf(DateTime.utc(2026, 9, 7));

      expect(
        (result as Err<List<WeeklyLeagueGroupRef>>).error.code,
        'gamification.weekly_league_id_malformed',
      );
    });

    test('passes a query failure through', () async {
      final result = await PostgresWeeklyLeagueClosureStore(
        _fails(),
      ).groupsOf(DateTime.utc(2026, 9, 7));

      expect(
        (result as Err<List<WeeklyLeagueGroupRef>>).error.code,
        'db.query_failed',
      );
    });
  });

  group('PostgresWeeklyLeagueClosureStore.markClosed', () {
    test('inserts one row for the week and never updates', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      final result = await PostgresWeeklyLeagueClosureStore(
        connection,
      ).markClosed(weekStart: DateTime.utc(2026, 9, 7), memberCount: 5);

      expect(result.isOk, isTrue);
      expect(connection.parameters.single['week_start'], '2026-09-07');
      expect(connection.parameters.single['member_count'], 5);

      // The table is append-only: a replay must be DO NOTHING, and no
      // statement here may be an UPDATE or a DELETE.
      final sql = connection.sqls.single.toUpperCase();
      expect(sql, contains('INSERT INTO GAMIFICATION.WEEKLY_LEAGUE_CLOSURES'));
      expect(sql, contains('ON CONFLICT (WEEK_START) DO NOTHING'));
      expect(sql, isNot(contains('UPDATE')));
      expect(sql, isNot(contains('DELETE')));
    });

    test('passes a query failure through', () async {
      final result = await PostgresWeeklyLeagueClosureStore(
        _fails(),
      ).markClosed(weekStart: DateTime.utc(2026, 9, 7), memberCount: 5);

      expect((result as Err<void>).error.code, 'db.query_failed');
    });
  });
}
