import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/leaderboard/postgres_sporting_season_standings_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _userId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

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

void main() {
  test(
    'reads combined score and streak-bonus points for a sporting season',
    () async {
      final conn = _rows([
        {
          'user_id': _userId,
          'display_name': 'Player One',
          'total_points': BigInt.from(37),
          'fixtures_scored': BigInt.from(4),
          'exact_count': BigInt.from(2),
          'decided_count': BigInt.from(4),
          'months_played': BigInt.from(2),
        },
      ]);
      final reader = PostgresSportingSeasonStandingsReader(conn);

      final result = await reader.standings(
        SportingSeason.containing(DateTime.utc(2026, 9, 1)),
      );

      expect(result, isA<Ok<List<SportingSeasonStanding>>>());
      final standings = (result as Ok<List<SportingSeasonStanding>>).value;
      expect(standings.single.userId, const UserId(_userId));
      expect(standings.single.totalPoints, 37);
      expect(standings.single.fixturesScored, 4);
      expect(standings.single.exactCount, 2);
      expect(standings.single.decidedCount, 4);
      expect(standings.single.monthsPlayed, 2);

      final sql = conn.sqls.single;
      expect(sql, contains('ledger.fixture_point_entries'));
      expect(sql, contains("e.entry_kind = 'streak_bonus'"));
      expect(sql, contains('competition.season_fixtures'));
      expect(sql, contains('LEFT JOIN bonuses'));
      expect(conn.parameters.single, {'first_key': 202609, 'last_key': 202708});
    },
  );

  test('preserves score-only and multiple-bonus mapped totals', () async {
    final conn = _rows([
      {
        'user_id': _userId,
        'display_name': 'Player One',
        'total_points': BigInt.from(11),
        'fixtures_scored': BigInt.one,
        'exact_count': BigInt.one,
        'decided_count': BigInt.one,
        'months_played': BigInt.one,
      },
      {
        'user_id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'display_name': 'Player Two',
        'total_points': BigInt.from(9),
        'fixtures_scored': BigInt.zero,
        'exact_count': BigInt.zero,
        'decided_count': BigInt.zero,
        'months_played': BigInt.from(2),
      },
    ]);
    final result = await PostgresSportingSeasonStandingsReader(
      conn,
    ).standings(SportingSeason.containing(DateTime.utc(2026, 9, 1)));
    final standings = (result as Ok<List<SportingSeasonStanding>>).value;
    expect(standings[0].totalPoints, 11);
    expect(standings[1].totalPoints, 9);
  });

  test('maps a bonus-only user with zero score counters', () async {
    final conn = _rows([
      {
        'user_id': _userId,
        'display_name': 'Player One',
        'total_points': BigInt.from(6),
        'fixtures_scored': BigInt.zero,
        'exact_count': BigInt.zero,
        'decided_count': BigInt.zero,
        'months_played': BigInt.one,
      },
    ]);
    final result = await PostgresSportingSeasonStandingsReader(
      conn,
    ).standings(SportingSeason.containing(DateTime.utc(2026, 9, 1)));
    final standings = (result as Ok<List<SportingSeasonStanding>>).value;
    expect(standings.single.totalPoints, 6);
    expect(standings.single.fixturesScored, 0);
    expect(standings.single.exactCount, 0);
    expect(standings.single.decidedCount, 0);
    expect(conn.sqls.single, contains('population AS'));
    expect(
      conn.sqls.single,
      contains('SELECT user_id, season_id FROM bonuses'),
    );
  });
}
