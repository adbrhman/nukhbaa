import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_league_store.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_newcomer_store.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_turn_keeper.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _league = '11111111-1111-4111-8111-000000000006';
const _userA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _userB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself, and every refusal of migration 0213, is exercised
/// end to end by `supabase/tests/0213_h2h_waiting_groups_test.sql`.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;

  final List<String> sqls = [];
  final List<Map<String, Object?>> parameters = [];
  int transactions = 0;

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
    transactions++;
    return action(this);
  }

  @override
  Future<void> close() async {}
}

_FakeConnection _answers(List<List<Map<String, dynamic>>> rows) =>
    _FakeConnection([for (final r in rows) Result.ok(r)]);

void main() {
  final december = DateTime.utc(2026, 12);

  test(
    'newcomersOf reads the players in the order the database gave',
    () async {
      final connection = _answers([
        [
          {'user_id': _userB, 'first_at': DateTime.utc(2026, 12, 2)},
          {'user_id': _userA, 'first_at': DateTime.utc(2026, 12, 3)},
        ],
      ]);

      final result = await PostgresH2hNewcomerStore(
        connection,
      ).newcomersOf(december);

      expect((result as Ok<List<UserId>>).value, [
        const UserId(_userB),
        const UserId(_userA),
      ]);
      expect(connection.sqls.single, PostgresH2hNewcomerStore.newcomersSql);
      expect(connection.parameters.single, {'month': '2026-12-01'});
    },
  );

  test('waitingGroupOf reads the open group, or none', () async {
    final open = await PostgresH2hNewcomerStore(
      _answers([
        [
          {'league_id': _league, 'group_index': 1, 'seated': BigInt.from(13)},
        ],
      ]),
    ).waitingGroupOf(december);
    final group = (open as Ok<H2hWaitingGroup?>).value!;
    expect(group.leagueId, const H2hLeagueId(_league));
    expect(group.groupIndex, 1);
    expect(group.seated, 13);

    final none = await PostgresH2hNewcomerStore(
      _answers([<Map<String, dynamic>>[]]),
    ).waitingGroupOf(december);
    expect((none as Ok<H2hWaitingGroup?>).value, isNull);
  });

  test('a corrupt row is an error, never a guess', () async {
    final result = await PostgresH2hNewcomerStore(
      _answers([
        [
          {'user_id': 'not-a-uuid'},
        ],
      ]),
    ).newcomersOf(december);

    expect(result, isA<Err<List<UserId>>>());
  });

  test('opening writes the group, its waiting row and its order of turns, '
      'in one transaction', () async {
    final connection = _answers([<Map<String, dynamic>>[]]);

    final result = await PostgresH2hNewcomerStore(connection).openWaitingGroup(
      monthStart: december,
      leagueId: const H2hLeagueId(_league),
      groupIndex: 2,
    );

    expect(result, isA<Ok<void>>());
    expect(connection.transactions, 1);
    expect(connection.sqls, [
      PostgresH2hLeagueStore.insertGroupSql,
      PostgresH2hLeagueStore.insertWaitingSql,
      PostgresH2hTurnKeeper.ensureSql,
    ]);
    expect(connection.parameters.first, {
      'id': _league,
      'month': '2026-12-01',
      'division': 2,
      'group_index': 2,
      'capacity': 20,
    });
  });

  test('the twentieth seat writes the seat, the record and the start, in '
      'one transaction; another seat no start', () async {
    final connection = _answers([<Map<String, dynamic>>[]]);
    final store = PostgresH2hNewcomerStore(connection);

    await store.seat(
      monthStart: december,
      leagueId: const H2hLeagueId(_league),
      userId: const UserId(_userA),
      slot: 19,
      startFrom: 8,
    );
    await store.seat(
      monthStart: december,
      leagueId: const H2hLeagueId(_league),
      userId: const UserId(_userB),
      slot: 3,
    );

    expect(connection.transactions, 2);
    expect(connection.sqls, [
      PostgresH2hLeagueStore.insertSeatSql,
      PostgresH2hNewcomerStore.newcomerSql,
      PostgresH2hNewcomerStore.startSql,
      PostgresH2hLeagueStore.insertSeatSql,
      PostgresH2hNewcomerStore.newcomerSql,
    ]);
    expect(connection.parameters[0], {
      'league_id': _league,
      'month': '2026-12-01',
      'user_id': _userA,
      'slot': 19,
    });
    expect(connection.parameters[2], {'league_id': _league, 'from_round': 8});
  });

  test('a failure is returned, not thrown', () async {
    final result = await PostgresH2hNewcomerStore(
      _FakeConnection([
        const Result.err(AppError.transient('db.down', 'Database down')),
      ]),
    ).nextExtraIndexOf(december);

    expect(result, isA<Err<int>>());
  });

  test(
    'the draw writes the waiting row right after its waiting group',
    () async {
      final connection = _answers([
        [
          {'inserted': 1},
        ],
        <Map<String, dynamic>>[],
      ]);

      await PostgresH2hLeagueStore(connection).draw(
        monthStart: december,
        isPilot: false,
        groups: const [
          H2hDrawnGroup(
            leagueId: H2hLeagueId(_league),
            group: H2hDrawGroup(
              division: H2hDivision.second,
              groupIndex: 1,
              waiting: true,
              seats: [H2hDrawSeat(userId: UserId(_userA), slot: 0)],
            ),
          ),
        ],
        capacity: 20,
      );

      expect(connection.sqls, [
        PostgresH2hLeagueStore.insertMonthSql,
        PostgresH2hLeagueStore.insertGroupSql,
        PostgresH2hLeagueStore.insertWaitingSql,
        PostgresH2hLeagueStore.insertSeatSql,
        PostgresH2hTurnKeeper.ensureSql,
      ]);
      expect(connection.parameters[2], {
        'league_id': _league,
        'month': '2026-12-01',
      });
    },
  );
}
