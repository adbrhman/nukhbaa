import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_league_store.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_newcomer_store.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_vacancy_store.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _league = '11111111-1111-4111-8111-000000000006';
const _waiting = '11111111-1111-4111-8111-000000000007';
const _vacancy = '33333333-3333-4333-8333-000000000001';
const _userA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _userB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself, and every refusal of migration 0214 (the
/// constraint names a ServerException carries, which has no public
/// constructor), is exercised end to end by
/// `supabase/tests/0214_h2h_absence_all_groups_test.sql`.
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

final _december = DateTime.utc(2026, 12);

H2hSeatVacancy _aVacancy() => H2hSeatVacancy(
  id: _vacancy,
  monthStart: _december,
  leagueId: const H2hLeagueId(_league),
  slot: 4,
  outUser: const UserId(_userA),
  fromRound: 6,
  absentRounds: [for (var n = 3; n <= 5; n++) (month: _december, round: n)],
);

H2hVacancyFill _aFill() => H2hVacancyFill(
  vacancyId: _vacancy,
  monthStart: _december,
  inUser: const UserId(_userB),
  fromRound: 6,
  fromLeagueId: const H2hLeagueId(_waiting),
  fromSlot: 2,
  facts: const H2hCandidateFacts(
    userId: UserId(_userB),
    missed: 1,
    points: 30,
    exact: 2,
    activeDays: 12,
    predicted: 40,
    outcomes: 9,
  ),
);

void main() {
  test('vacanciesOf reads each seat left, with its fill or none', () async {
    final connection = _answers([
      [
        {
          'id': _vacancy,
          'league_id': _league,
          'slot': 4,
          'out_user': _userA,
          'from_round': 6,
          'in_user': _userB,
          'filled_from': 7,
        },
        {
          'id': '33333333-3333-4333-8333-000000000002',
          'league_id': _league,
          'slot': 5,
          'out_user': _userB,
          'from_round': 6,
          'in_user': null,
          'filled_from': null,
        },
      ],
    ]);

    final result = await PostgresH2hVacancyStore(
      connection,
    ).vacanciesOf(_december);

    final vacancies = (result as Ok<List<H2hSeatVacancy>>).value;
    expect(connection.sqls.single, PostgresH2hVacancyStore.vacanciesSql);
    expect(connection.parameters.single, {'month': '2026-12-01'});
    expect(vacancies.first.leagueId, const H2hLeagueId(_league));
    expect(vacancies.first.slot, 4);
    expect(vacancies.first.filledBy, const UserId(_userB));
    expect(vacancies.first.filledFrom, 7);
    expect(vacancies.first.filled, isTrue);
    expect(vacancies.last.filled, isFalse);
    expect(vacancies.last.filledFrom, isNull);
  });

  test('a corrupt row is an error, never a guess', () async {
    final result = await PostgresH2hVacancyStore(
      _answers([
        [
          {
            'id': _vacancy,
            'league_id': _league,
            'slot': 4,
            'out_user': 'not-a-uuid',
            'from_round': 6,
          },
        ],
      ]),
    ).vacanciesOf(_december);

    expect(result, isA<Err<List<H2hSeatVacancy>>>());
  });

  test('a vacancy and its fill are written in ONE transaction', () async {
    final connection = _answers([<Map<String, dynamic>>[]]);

    final result = await PostgresH2hVacancyStore(
      connection,
    ).vacate(vacancy: _aVacancy(), fill: _aFill());

    expect(result, isA<Ok<void>>());
    expect(connection.transactions, 1);
    expect(connection.sqls, [
      PostgresH2hVacancyStore.insertVacancySql,
      PostgresH2hVacancyStore.insertFillSql,
    ]);
    expect(connection.parameters.first, {
      'id': _vacancy,
      'month': '2026-12-01',
      'league_id': _league,
      'slot': 4,
      'out_user': _userA,
      'from_round': 6,
      'absent_rounds': jsonEncode([
        for (var n = 3; n <= 5; n++) {'month': '2026-12-01', 'round': n},
      ]),
    });
    final fill = connection.parameters.last;
    expect(fill['vacancy_id'], _vacancy);
    expect(fill['in_user'], _userB);
    expect(fill['from_league_id'], _waiting);
    expect(fill['from_slot'], 2);
    expect(fill['from_round'], 6);
    final candidate =
        jsonDecode(fill['candidate']! as String) as Map<String, dynamic>;
    expect(candidate['predicted'], 40);
    expect(candidate['outcomes'], 9);
  });

  test('a vacancy with nobody to fill it is written alone', () async {
    final connection = _answers([<Map<String, dynamic>>[]]);

    await PostgresH2hVacancyStore(connection).vacate(vacancy: _aVacancy());

    expect(connection.transactions, 1);
    expect(connection.sqls, [PostgresH2hVacancyStore.insertVacancySql]);
  });

  test('a failed fill fails the whole transaction', () async {
    final connection = _FakeConnection([
      const Result.ok(<Map<String, dynamic>>[]),
      const Result.err(AppError.transient('db.timeout', 'timed out')),
    ]);

    final result = await PostgresH2hVacancyStore(
      connection,
    ).vacate(vacancy: _aVacancy(), fill: _aFill());

    expect((result as Err<void>).error.code, 'db.timeout');
    expect(connection.transactions, 1);
  });

  test('a later fill is one statement', () async {
    final connection = _answers([<Map<String, dynamic>>[]]);

    final result = await PostgresH2hVacancyStore(connection).fill(_aFill());

    expect(result, isA<Ok<void>>());
    expect(connection.sqls, [PostgresH2hVacancyStore.insertFillSql]);
  });

  group('a waiting seat taken again (NK278)', () {
    Future<_FakeConnection> seat({
      required bool returning,
      required bool slotUsed,
    }) async {
      final connection = _answers([
        [
          {'is_return': returning, 'slot_used': slotUsed},
        ],
        <Map<String, dynamic>>[],
      ]);
      await PostgresH2hNewcomerStore(connection).seat(
        monthStart: _december,
        leagueId: const H2hLeagueId(_waiting),
        userId: const UserId(_userA),
        slot: 2,
      );
      return connection;
    }

    test('a player back from absence takes it as a return', () async {
      final connection = await seat(returning: true, slotUsed: false);
      expect(connection.sqls, [
        PostgresH2hNewcomerStore.seatKindSql,
        PostgresH2hNewcomerStore.waitingSeatSql,
      ]);
      expect(connection.parameters.last, {
        'month': '2026-12-01',
        'user_id': _userA,
        'league_id': _waiting,
        'slot': 2,
        'reason': 'return',
      });
    });

    test(
      'a new player on a seat a filler left takes it as a newcomer',
      () async {
        final connection = await seat(returning: false, slotUsed: true);
        expect(connection.sqls.last, PostgresH2hNewcomerStore.waitingSeatSql);
        expect(connection.parameters.last['reason'], 'newcomer');
      },
    );

    test('a seat never taken is a new seat, as in 0213', () async {
      final connection = await seat(returning: false, slotUsed: false);
      expect(connection.sqls, [
        PostgresH2hNewcomerStore.seatKindSql,
        PostgresH2hLeagueStore.insertSeatSql,
        PostgresH2hNewcomerStore.newcomerSql,
      ]);
    });

    test('the waiting group reads its free seat', () async {
      final read = await PostgresH2hNewcomerStore(
        _answers([
          [
            {
              'league_id': _waiting,
              'group_index': 2,
              'seated': 18,
              'free_slot': 3,
            },
          ],
        ]),
      ).waitingGroupOf(_december);
      final group = (read as Ok<H2hWaitingGroup?>).value!;
      expect(group.seated, 18);
      expect(group.nextSlot, 3);
    });
  });
}
