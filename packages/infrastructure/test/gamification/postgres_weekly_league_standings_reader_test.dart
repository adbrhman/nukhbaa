import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_weekly_league_standings_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _league = '11111111-1111-1111-1111-111111111111';
const _userA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _userB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

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

Future<Result<List<WeeklyLeagueEntry>>> _read(
  _FakeConnection connection, {
  DateTime? weekStart,
}) => PostgresWeeklyLeagueStandingsReader(connection).entriesOf(
  leagueId: const WeeklyLeagueId(_league),
  weekStart: weekStart ?? DateTime.utc(2026, 9, 21),
);

void main() {
  group('PostgresWeeklyLeagueStandingsReader.entriesOf', () {
    test('maps each member row to a week entry', () async {
      final connection = _rows([
        {
          'user_id': _userA,
          'joined_at': DateTime.utc(2026, 9, 21, 9),
          'total_points': BigInt.from(17),
          'exact_count': BigInt.from(2),
          'decided_count': BigInt.from(5),
        },
        {
          'user_id': _userB,
          'joined_at': '2026-09-22T10:30:00Z',
          'total_points': 0,
          'exact_count': '0',
          'decided_count': 0,
        },
      ]);

      final result = await _read(connection);

      final entries = (result as Ok<List<WeeklyLeagueEntry>>).value;
      expect(entries, hasLength(2));
      expect(entries.first.userId, const UserId(_userA));
      expect(entries.first.points, 17);
      expect(entries.first.exactCount, 2);
      expect(entries.first.decidedCount, 5);
      expect(entries.first.joinedAt, DateTime.utc(2026, 9, 21, 9));
      expect(entries.last.userId, const UserId(_userB));
      expect(entries.last.points, 0);
      expect(entries.last.exactCount, 0);
      expect(entries.last.joinedAt, DateTime.utc(2026, 9, 22, 10, 30));
    });

    test('an empty group is an empty list, not an error', () async {
      final result = await _read(_rows(const <Map<String, dynamic>>[]));
      expect((result as Ok<List<WeeklyLeagueEntry>>).value, isEmpty);
    });

    test('binds the group and the inclusive Monday-Sunday window', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      await _read(connection);

      expect(connection.parameters.single, {
        'league_id': _league,
        'week_start': '2026-09-21',
        'week_end': '2026-09-27',
      });
    });

    test('a mid-week start is normalised to its Monday', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      await _read(connection, weekStart: DateTime.utc(2026, 9, 23));

      expect(connection.parameters.single, {
        'league_id': _league,
        'week_start': '2026-09-21',
        'week_end': '2026-09-27',
      });
    });

    test('sums the monthly board sources over the Riyadh week', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      await _read(connection);

      final sql = connection.sqls.single;
      expect(sql, contains('scoring.fixture_scores'));
      expect(sql, contains('ledger.fixture_point_entries'));
      expect(sql, contains("entry_kind = 'streak_bonus'"));
      expect(sql, contains("AT TIME ZONE 'Asia/Riyadh'"));
      expect(sql, contains('BETWEEN @week_start::date AND @week_end::date'));
      // The grade buckets are the monthly board's: decided excludes pending.
      expect(
        sql,
        contains("IN ('exact_scoreline', 'correct_outcome', 'incorrect')"),
      );
    });

    test('goes through the season fixtures, as the month does', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      await _read(connection);

      expect(connection.sqls.single, contains('competition.season_fixtures'));
    });

    test(
      'starts from the group so a member who scored nothing shows',
      () async {
        final connection = _rows(const <Map<String, dynamic>>[]);

        await _read(connection);

        final sql = connection.sqls.single;
        expect(sql, contains('gamification.weekly_league_members'));
        expect(sql, contains('FROM members mb'));
        expect(sql, contains('LEFT JOIN scores s'));
        expect(sql, contains('LEFT JOIN bonuses b'));
      },
    );

    test('sums across participations and applies no season window', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      await _read(connection);

      final sql = connection.sqls.single;
      expect(sql, contains('competition.participants'));
      expect(sql, contains("'active'::competition.participant_status"));
      expect(sql, isNot(contains('start_at')));
      expect(sql, isNot(contains('end_at')));
    });

    test('a database failure is returned, not swallowed', () async {
      final result = await _read(_fails());

      expect(result, isA<Err<List<WeeklyLeagueEntry>>>());
      expect(
        (result as Err<List<WeeklyLeagueEntry>>).error.code,
        'db.query_failed',
      );
    });

    test('a malformed user id is a corrupt row, not a crash', () async {
      final result = await _read(
        _rows([
          {
            'user_id': 'not-a-uuid',
            'joined_at': DateTime.utc(2026, 9, 21, 9),
            'total_points': 1,
            'exact_count': 0,
            'decided_count': 0,
          },
        ]),
      );

      expect(
        (result as Err<List<WeeklyLeagueEntry>>).error.code,
        'gamification.weekly_league_row_corrupt',
      );
    });

    test('an unreadable count is a corrupt row', () async {
      final result = await _read(
        _rows([
          {
            'user_id': _userA,
            'joined_at': DateTime.utc(2026, 9, 21, 9),
            'total_points': 'many',
            'exact_count': 0,
            'decided_count': 0,
          },
        ]),
      );

      expect(
        (result as Err<List<WeeklyLeagueEntry>>).error.code,
        'gamification.weekly_league_row_corrupt',
      );
    });

    test('an unreadable seat time is a corrupt row', () async {
      final result = await _read(
        _rows([
          {
            'user_id': _userA,
            'joined_at': null,
            'total_points': 1,
            'exact_count': 0,
            'decided_count': 0,
          },
        ]),
      );

      expect(
        (result as Err<List<WeeklyLeagueEntry>>).error.code,
        'gamification.weekly_league_row_corrupt',
      );
    });
  });
}
