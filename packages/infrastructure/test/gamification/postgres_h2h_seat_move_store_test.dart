import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_seat_move_store.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _month = '2026-11-01';
const _move = '33333333-3333-4333-8333-333333333333';
const _elite = '11111111-1111-4111-8111-000000000001';
const _extra = '11111111-1111-4111-8111-000000000005';
const _round = '22222222-2222-4222-8222-000000000003';
const _userA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _userB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _admin = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself is exercised end to end by
/// `supabase/tests/0189_h2h_seat_moves_test.sql`.
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

_FakeConnection _answers(List<List<Map<String, dynamic>>> rows) =>
    _FakeConnection([for (final r in rows) Result.ok(r)]);

H2hSeatMove _aMove({H2hSeatMoveKind kind = H2hSeatMoveKind.absence}) =>
    H2hSeatMove(
      id: _move,
      monthStart: DateTime.utc(2026, 11),
      fromRound: 4,
      kind: kind,
      outUser: const UserId(_userA),
      inUser: const UserId(_userB),
      eliteLeagueId: const H2hLeagueId(_elite),
      eliteSlot: 0,
      extraLeagueId: const H2hLeagueId(_extra),
      extraSlot: 2,
      absentRounds: [(month: DateTime.utc(2026, 11), round: 3)],
      facts: const H2hCandidateFacts(
        userId: UserId(_userB),
        missed: 2,
        points: 40,
        exact: 3,
        activeDays: 19,
      ),
      reason: kind == H2hSeatMoveKind.admin ? 'تلاعب' : null,
      decidedBy: kind == H2hSeatMoveKind.admin ? const UserId(_admin) : null,
      createdAt: DateTime.utc(2026, 11, 4, 14),
    );

void main() {
  group('PostgresH2hSeatMoveStore', () {
    test('reads a month\'s swaps with their rounds and facts', () async {
      final connection = _answers([
        [
          {
            'id': _move,
            'month': _month,
            'from_round': 4,
            'kind': 'admin',
            'out_user': _userA,
            'in_user': _userB,
            'elite_league_id': _elite,
            'elite_slot': 0,
            'extra_league_id': _extra,
            'extra_slot': 2,
            'absent_rounds': '[{"month":"2026-11-01","round":3}]',
            'candidate':
                '{"user_id":"$_userB","missed":2,"points":40,"exact":3,'
                '"active_days":19}',
            'reason': 'تلاعب',
            'decided_by': _admin,
            'created_at': DateTime.utc(2026, 11, 4, 14),
          },
        ],
      ]);

      final result = await PostgresH2hSeatMoveStore(
        connection,
      ).movesOf(DateTime.utc(2026, 11));

      final move = (result as Ok<List<H2hSeatMove>>).value.single;
      expect(move.kind, H2hSeatMoveKind.admin);
      expect(move.fromRound, 4);
      expect(move.outUser, const UserId(_userA));
      expect(move.extraSlot, 2);
      expect(move.absentRounds.single.round, 3);
      expect(move.facts!.activeDays, 19);
      expect(move.reason, 'تلاعب');
      expect(move.decidedBy, const UserId(_admin));
      expect(connection.parameters.single, {'month': _month});
    });

    test(
      'attendance: the round\'s players, its fixtures, its last kickoff',
      () async {
        final connection = _answers([
          [
            {
              'round_id': _round,
              'fixtures': 7,
              'last_kickoff': DateTime.utc(2026, 11, 3, 20),
              'present': '$_userA,$_userB',
            },
          ],
        ]);
        final round = H2hRound(
          id: const H2hRoundId(_round),
          monthStart: DateTime.utc(2026, 11),
          number: 3,
          day: DateTime.utc(2026, 11, 3),
          fixtureCount: 7,
          approvedBy: null,
          lockedAt: DateTime.utc(2026, 11, 3, 12),
        );

        final result = await PostgresH2hSeatMoveStore(
          connection,
        ).attendance([round]);

        final attendance =
            (result as Ok<List<H2hRoundAttendance>>).value.single;
        expect(attendance.fixtures, 7);
        expect(attendance.present, {
          const UserId(_userA),
          const UserId(_userB),
        });
        expect(connection.parameters.single, {'round_ids': _round});
      },
    );

    test('no rounds, no query', () async {
      final connection = _answers([<Map<String, dynamic>>[]]);

      final result = await PostgresH2hSeatMoveStore(connection).attendance([]);

      expect((result as Ok<List<H2hRoundAttendance>>).value, isEmpty);
      expect(connection.sqls, isEmpty);
    });

    test('a swap is written with its admin-log row', () async {
      final connection = _answers([<Map<String, dynamic>>[]]);

      final result = await PostgresH2hSeatMoveStore(connection).recordMove(
        move: _aMove(kind: H2hSeatMoveKind.admin),
        logId: '44444444-4444-4444-8444-444444444444',
      );

      expect(result.isOk, isTrue);
      expect(connection.sqls, [
        PostgresH2hSeatMoveStore.insertMoveSql,
        PostgresH2hSeatMoveStore.logSql,
      ]);
      expect(connection.parameters[0]['kind'], 'admin');
      expect(connection.parameters[0]['decided_by'], _admin);
      expect(connection.parameters[0]['from_round'], 4);
      expect(
        connection.parameters[0]['absent_rounds'],
        '[{"month":"2026-11-01","round":3}]',
      );
      expect(connection.parameters[1]['action'], 'seat_moved');
      expect(connection.parameters[1]['actor'], _admin);
    });

    test('a failure that is not a refusal stays what it was', () async {
      // A refusal (`h2h.move_refused`) needs a real ServerException, which
      // has no public constructor: the constraint names are checked end to
      // end by supabase/tests/0189_h2h_seat_moves_test.sql.
      final connection = _FakeConnection([
        const Result.err(AppError.transient('db.timeout', 'timed out')),
      ]);

      final result = await PostgresH2hSeatMoveStore(connection).recordMove(
        move: _aMove(),
        logId: '44444444-4444-4444-8444-444444444444',
      );

      expect((result as Err<void>).error.code, 'db.timeout');
      expect(result.error.kind, ErrorKind.transient);
      expect(connection.sqls, [PostgresH2hSeatMoveStore.insertMoveSql]);
    });

    test('a warning is new once; the facts read the window', () async {
      final warned =
          await PostgresH2hSeatMoveStore(
            _answers([
              [
                {'warned': 1},
              ],
            ]),
          ).recordWarning(
            roundId: const H2hRoundId(_round),
            userId: const UserId(_userA),
          );
      final again =
          await PostgresH2hSeatMoveStore(
            _answers([<Map<String, dynamic>>[]]),
          ).recordWarning(
            roundId: const H2hRoundId(_round),
            userId: const UserId(_userA),
          );
      final factsConnection = _answers([
        [
          {
            'user_id': _userB,
            'missed': 2,
            'points': 40,
            'exact': 3,
            'active_days': 19,
          },
        ],
      ]);
      final facts = await PostgresH2hSeatMoveStore(factsConnection)
          .candidateFacts(
            lastDay: DateTime.utc(2026, 11, 3),
            users: const [UserId(_userB)],
          );

      expect((warned as Ok<bool>).value, isTrue);
      expect((again as Ok<bool>).value, isFalse);
      expect((facts as Ok<List<H2hCandidateFacts>>).value.single.missed, 2);
      expect(factsConnection.parameters.single, {
        'last_day': '2026-11-03',
        'days': H2hAbsencePolicy.windowDays,
        'user_ids': _userB,
      });
    });
  });
}
