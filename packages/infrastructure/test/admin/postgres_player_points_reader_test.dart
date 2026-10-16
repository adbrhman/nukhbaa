import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/admin/postgres_player_points_reader.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
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

const String _user = '00000000-146b-4000-8000-000000000001';
const String _season = '00000000-146b-4000-8000-0000000000a1';
const String _participant = '00000000-146b-4000-8000-0000000000b1';

Future<PlayerMonthPoints> _read(_FakeConnection connection) async {
  final Result<PlayerMonthPoints> result = await PostgresPlayerPointsReader(
    connection,
  ).pointsOf(user: const UserId(_user), season: const SeasonId(_season));
  return (result as Ok<PlayerMonthPoints>).value;
}

/// The row mapping of a player's month (batch 146b). The SQL is checked
/// against the schema by `player_points_query_test.sql`.
void main() {
  test(
    'every movement with its match, the month and the bonus apart',
    () async {
      final _FakeConnection connection = _FakeConnection(
        Result.ok([
          {
            'participant_id': _participant,
            'id': 'e1',
            'fixture_id': 'f1',
            'home_team': 'Arsenal',
            'away_team': 'Chelsea',
            'kind': 'fixture_score',
            'amount': 3,
            'occurred_at': DateTime.utc(2026, 10, 10, 21),
          },
          {
            'participant_id': _participant,
            'id': 'e2',
            'fixture_id': 'f1',
            'home_team': 'Arsenal',
            'away_team': 'Chelsea',
            'kind': 'streak_bonus',
            'amount': 2,
            'occurred_at': DateTime.utc(2026, 10, 10, 21, 1),
          },
          {
            'participant_id': _participant,
            'id': 'e3',
            'fixture_id': 'f2',
            'home_team': null,
            'away_team': null,
            'kind': 'correction',
            'amount': -1,
            'occurred_at': '2026-10-12T09:00:00Z',
          },
        ]),
      );

      final PlayerMonthPoints month = await _read(connection);

      expect(month.participantId, _participant);
      expect(month.entries.map((e) => e.id), ['e1', 'e2', 'e3']);
      expect(month.entries.first.homeTeam, 'Arsenal');
      expect(month.entries.last.occurredAt, DateTime.utc(2026, 10, 12, 9));
      expect(month.monthPoints, 2, reason: 'a match score and its correction');
      expect(month.streakBonus, 2, reason: 'the weekly league only');
      expect(connection.sqls, [PostgresPlayerPointsReader.pointsSql]);
      expect(connection.params.single, {
        'user_id': _user,
        'season_id': _season,
      });
    },
  );

  test('played without a movement: his place, no entry', () async {
    final PlayerMonthPoints month = await _read(
      _FakeConnection(
        const Result.ok([
          {'participant_id': _participant, 'id': null},
        ]),
      ),
    );

    expect(month.participantId, _participant);
    expect(month.entries, isEmpty);
  });

  test('never played in the month: no place, no entry', () async {
    final PlayerMonthPoints month = await _read(
      _FakeConnection(const Result.ok([])),
    );

    expect(month.participantId, isNull);
    expect(month.monthPoints, 0);
  });
}
