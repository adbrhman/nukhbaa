import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_streak_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Hermetic unit tests for [PostgresStreakRepository]: a fake
/// [PostgresConnection] replays scripted rows and records the SQL and the
/// parameters. That the calendar returns the right days is checked by hand
/// against the live database, because only a real server runs the query.
void main() {
  group('PostgresStreakRepository.completionCalendar', () {
    test('maps each row to a match day and its completion', () async {
      final connection = _rows([
        {'day': DateTime.utc(2026, 9, 19), 'completed': true},
        {'day': '2026-09-18', 'completed': false},
      ]);

      final result = await PostgresStreakRepository(connection)
          .completionCalendar(
            userId: const UserId('user-1'),
            upToDay: DateTime.utc(2026, 9, 19),
            limitDays: 400,
          );

      final calendar = (result as Ok<List<MatchDayCompletion>>).value;
      expect(calendar, hasLength(2));
      expect(calendar.first.day, DateTime.utc(2026, 9, 19));
      expect(calendar.first.completed, isTrue);
      expect(calendar.last.day, DateTime.utc(2026, 9, 18));
      expect(calendar.last.completed, isFalse);
    });

    test('binds the day twice, the limit and the user twice', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      await PostgresStreakRepository(connection).completionCalendar(
        userId: const UserId('user-1'),
        upToDay: DateTime.utc(2026, 9, 19),
        limitDays: 400,
      );

      expect(connection.parameters.single, {
        'up_to': '2026-09-19',
        'live_up_to': '2026-09-19',
        'limit_days': 400,
        'user_id': 'user-1',
        'user_key': 'user-1',
      });
    });

    test(
      'reads settled days as frozen and computes only newer days live',
      () async {
        final connection = _rows(const <Map<String, dynamic>>[]);

        await PostgresStreakRepository(connection).completionCalendar(
          userId: const UserId('user-1'),
          upToDay: DateTime.utc(2026, 9, 19),
          limitDays: 400,
        );

        final sql = connection.sqls.single;
        expect(sql, contains('gamification.settled_days'));
        expect(sql, contains('fixture_count > 0'));
        // With nothing settled the live branch covers every day, as before.
        expect(sql, contains("'-infinity'::date"));
      },
    );

    test('counts only the days the reader own seasons played', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      await PostgresStreakRepository(connection).completionCalendar(
        userId: const UserId('user-1'),
        upToDay: DateTime.utc(2026, 9, 19),
        limitDays: 400,
      );

      final sql = connection.sqls.single;
      // Both branches -- the frozen one and the live one -- are joined to the
      // reader own active participations, so a day only other seasons played
      // is not a match day for this reader.
      expect(sql, contains('competition.participants'));
      expect(
        sql,
        contains("p.status = 'active'::competition.participant_status"),
      );
      expect(sql, contains('gamification.settled_day_seasons'));
      expect('ON ms.season_id'.allMatches(sql).length, 2);
    });

    test('passes a query failure through', () async {
      final result = await PostgresStreakRepository(_fails())
          .completionCalendar(
            userId: const UserId('user-1'),
            upToDay: DateTime.utc(2026, 9, 19),
            limitDays: 400,
          );

      expect(
        (result as Err<List<MatchDayCompletion>>).error.code,
        'db.query_failed',
      );
    });
  });
}

/// A [PostgresConnection] test double that replays a scripted queue of
/// [Result]s (one per `query`) and records every SQL and parameter set.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;

  final List<String> sqls = <String>[];
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

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
  ) async {
    return action(this);
  }

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
