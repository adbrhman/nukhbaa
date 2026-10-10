import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_group_extension.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _u1 = UserId('00000000-0000-4000-9000-000000000001');
const _u2 = UserId('00000000-0000-4000-9000-000000000002');
const _u3 = UserId('00000000-0000-4000-9000-000000000003');

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself is exercised end to end by
/// `supabase/tests/0102_h2h_groups_added_test.sql`.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;
  int transactions = 0;

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
  ) async {
    transactions++;
    return action(this);
  }

  @override
  Future<void> close() async {}
}

H2hDrawnGroup _group(String id, H2hDivision division, List<UserId> users) =>
    H2hDrawnGroup(
      leagueId: H2hLeagueId(id),
      group: H2hDrawGroup(
        division: division,
        groupIndex: 0,
        seats: [
          for (var i = 0; i < users.length; i++)
            H2hDrawSeat(userId: users[i], slot: i),
        ],
      ),
    );

void main() {
  group('PostgresH2hGroupExtension', () {
    test('reads the players waiting, in the order given', () async {
      final connection = _FakeConnection([
        Result.ok([
          {'user_id': _u2.value},
          {'user_id': _u1.value},
        ]),
      ]);

      final result = await PostgresH2hGroupExtension(connection)
          .waitingByParticipation(
            monthStart: DateTime.utc(2026, 10),
            minActiveDays: 5,
          );

      expect((result as Ok<List<UserId>>).value, [_u2, _u1]);
      expect(connection.sqls.single, PostgresH2hGroupExtension.waitingSql);
      expect(connection.parameters.single, {
        'month': '2026-10-01',
        'min_days': 5,
      });
    });

    test('a stored id that is not a user id is a corrupt row', () async {
      final result =
          await PostgresH2hGroupExtension(
            _FakeConnection([
              Result.ok([
                {'user_id': 'x'},
              ]),
            ]),
          ).waitingByParticipation(
            monthStart: DateTime.utc(2026, 10),
            minActiveDays: 5,
          );

      expect(
        (result as Err<List<UserId>>).error.code,
        'gamification.h2h_row_corrupt',
      );
    });

    test('writes each group, then its seats, in one transaction', () async {
      final connection = _FakeConnection([
        const Result.ok(<Map<String, dynamic>>[]),
      ]);

      final result = await PostgresH2hGroupExtension(connection).addGroups(
        monthStart: DateTime.utc(2026, 10),
        groups: [
          _group('22222222-2222-4222-8222-222222222222', H2hDivision.second, [
            _u1,
            _u2,
          ]),
          _group('33333333-3333-4333-8333-333333333333', H2hDivision.third, [
            _u3,
          ]),
        ],
        capacity: 20,
      );

      expect((result as Ok<int>).value, 3);
      expect(connection.transactions, 1);
      expect(connection.sqls, [
        PostgresH2hGroupExtension.insertGroupSql,
        PostgresH2hGroupExtension.insertSeatSql,
        PostgresH2hGroupExtension.insertSeatSql,
        PostgresH2hGroupExtension.insertGroupSql,
        PostgresH2hGroupExtension.insertSeatSql,
      ]);
      expect(connection.parameters.first, {
        'id': '22222222-2222-4222-8222-222222222222',
        'month': '2026-10-01',
        'division': 2,
        'group_index': 0,
        'capacity': 20,
      });
      expect(connection.parameters[2], {
        'league_id': '22222222-2222-4222-8222-222222222222',
        'month': '2026-10-01',
        'user_id': _u2.value,
        'slot': 1,
      });
    });

    test('a failed write stops at once and is answered', () async {
      final connection = _FakeConnection([
        const Result.err(AppError.transient('db.query_failed', 'down')),
      ]);

      final result = await PostgresH2hGroupExtension(connection).addGroups(
        monthStart: DateTime.utc(2026, 10),
        groups: [
          _group('22222222-2222-4222-8222-222222222222', H2hDivision.second, [
            _u1,
          ]),
        ],
        capacity: 20,
      );

      expect((result as Err<int>).error.code, 'db.query_failed');
      expect(connection.sqls, hasLength(1));
    });
  });
}
