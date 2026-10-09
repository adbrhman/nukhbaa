import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_draw_source.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_league_store.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_round_store.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_sheet_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _league = '11111111-1111-4111-8111-111111111111';
const _round = '22222222-2222-4222-8222-222222222222';
const _userA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _userB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself is exercised end to end by
/// `supabase/tests/0100_h2h_queries_test.sql`.
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

void main() {
  group('PostgresH2hLeagueStore', () {
    test('reads a month row', () async {
      final connection = _answers([
        [
          {'is_pilot': true, 'seated_count': BigInt.from(6)},
        ],
      ]);

      final result = await PostgresH2hLeagueStore(
        connection,
      ).monthOf(DateTime.utc(2026, 10, 17));

      final info = (result as Ok<H2hMonthInfo?>).value!;
      expect(info.isPilot, isTrue);
      expect(info.seatedCount, 6);
      expect(info.monthStart, DateTime.utc(2026, 10, 17));
      expect(connection.parameters.single['month'], '2026-10-17');
    });

    test('a drawn month writes nothing more and returns 0', () async {
      final connection = _answers([<Map<String, dynamic>>[]]);

      final result = await PostgresH2hLeagueStore(connection).draw(
        monthStart: DateTime.utc(2026, 11),
        isPilot: false,
        groups: const <H2hDrawnGroup>[],
        capacity: 20,
      );

      expect((result as Ok<int>).value, 0);
      expect(connection.sqls, hasLength(1));
    });

    test('a draw writes the month, each group and each seat', () async {
      final connection = _answers([
        [
          {'inserted': 1},
        ],
        <Map<String, dynamic>>[],
      ]);
      final groups = [
        const H2hDrawnGroup(
          leagueId: H2hLeagueId(_league),
          group: H2hDrawGroup(
            division: H2hDivision.first,
            groupIndex: 0,
            seats: [
              H2hDrawSeat(userId: UserId(_userA), slot: 0),
              H2hDrawSeat(userId: UserId(_userB), slot: 1),
            ],
          ),
        ),
      ];

      final result = await PostgresH2hLeagueStore(connection).draw(
        monthStart: DateTime.utc(2026, 11),
        isPilot: true,
        groups: groups,
        capacity: 20,
      );

      expect((result as Ok<int>).value, 2);
      expect(connection.sqls, hasLength(4));
      expect(connection.parameters[0]['is_pilot'], isTrue);
      expect(connection.parameters[0]['seated'], 2);
      expect(connection.parameters[1]['division'], 1);
      expect(connection.parameters[3]['user_id'], _userB);
      expect(connection.parameters[3]['slot'], 1);
    });

    test('maps a seat', () async {
      final connection = _answers([
        [
          {
            'league_id': _league,
            'division': 2,
            'group_index': 0,
            'slot': 7,
            'capacity': 20,
            'joined_at': DateTime.utc(2026, 11, 1, 0, 5),
            'is_pilot': false,
            'division_groups': 1,
          },
        ],
      ]);

      final result = await PostgresH2hLeagueStore(connection).seatFor(
        userId: const UserId(_userA),
        monthStart: DateTime.utc(2026, 11),
      );

      final seat = (result as Ok<H2hSeat?>).value!;
      expect(seat.division, H2hDivision.second);
      expect(seat.slot, 7);
      expect(seat.divisionGroups, 1);
      expect(seat.monthStart, DateTime.utc(2026, 11));
    });

    test('an unreadable seat is a transient error, not a crash', () async {
      final connection = _answers([
        [
          {'league_id': 'nope', 'division': 9},
        ],
      ]);

      final result = await PostgresH2hLeagueStore(connection).seatFor(
        userId: const UserId(_userA),
        monthStart: DateTime.utc(2026, 11),
      );

      expect((result as Err<H2hSeat?>).error.kind, ErrorKind.transient);
    });

    test('the oldest unclosed month, or none', () async {
      final some = await PostgresH2hLeagueStore(
        _answers([
          [
            {'month': '2026-11-01'},
          ],
        ]),
      ).nextUnclosedMonth();
      final none = await PostgresH2hLeagueStore(
        _answers([
          [
            {'month': null},
          ],
        ]),
      ).nextUnclosedMonth();

      expect((some as Ok<DateTime?>).value, DateTime.utc(2026, 11));
      expect((none as Ok<DateTime?>).value, isNull);
    });
  });

  group('PostgresH2hRoundStore', () {
    test('maps rounds, an automatic approval and a lock', () async {
      final connection = _answers([
        [
          {
            'id': _round,
            'round_no': 1,
            'day': '2026-11-03',
            'fixture_count': 9,
            'approved_by': null,
            'locked_at': DateTime.utc(2026, 11, 3, 12),
          },
          {
            'id': '33333333-3333-4333-8333-333333333333',
            'round_no': 2,
            'day': '2026-11-05',
            'fixture_count': 6,
            'approved_by': _userA,
            'locked_at': null,
          },
        ],
      ]);

      final result = await PostgresH2hRoundStore(
        connection,
      ).roundsOf(DateTime.utc(2026, 11));

      final rounds = (result as Ok<List<H2hRound>>).value;
      expect(rounds.map((r) => r.number).toList(), [1, 2]);
      expect(rounds.first.locked, isTrue);
      expect(rounds.first.approvedBy, isNull);
      expect(rounds.first.day, DateTime.utc(2026, 11, 3));
      expect(rounds.last.locked, isFalse);
      expect(rounds.last.approvedBy, const UserId(_userA));
    });

    test('a day with no fixture reads as zero', () async {
      final result = await PostgresH2hRoundStore(
        _answers([<Map<String, dynamic>>[]]),
      ).dayFixtures(DateTime.utc(2026, 11, 9, 13));

      final day = (result as Ok<H2hDayFixtures>).value;
      expect(day.fixtureCount, 0);
      expect(day.firstKickoff, isNull);
      expect(day.day, DateTime.utc(2026, 11, 9));
    });

    test('an automatic approval binds no approver', () async {
      final connection = _answers([<Map<String, dynamic>>[]]);

      final result = await PostgresH2hRoundStore(connection).approve(
        id: const H2hRoundId(_round),
        monthStart: DateTime.utc(2026, 11),
        number: 3,
        day: DateTime.utc(2026, 11, 8),
        fixtureCount: 7,
        approvedBy: null,
      );

      expect(result.isOk, isTrue);
      expect(connection.parameters.single['approved_by'], isNull);
      expect(connection.parameters.single['day'], '2026-11-08');
      expect(connection.parameters.single['round_no'], 3);
    });

    test('withdrawing an unknown round is a validation error', () async {
      final result = await PostgresH2hRoundStore(
        _answers([<Map<String, dynamic>>[]]),
      ).withdraw(const H2hRoundId(_round));

      expect((result as Err<void>).error.code, 'h2h.round_unknown');
    });

    test('a lock freezes, locks and reads the frozen count', () async {
      final connection = _answers([
        <Map<String, dynamic>>[],
        <Map<String, dynamic>>[],
        [
          {'fixture_count': 9},
        ],
      ]);

      final result = await PostgresH2hRoundStore(
        connection,
      ).lock(roundId: const H2hRoundId(_round), day: DateTime.utc(2026, 11, 3));

      expect((result as Ok<int>).value, 9);
      expect(connection.sqls, hasLength(3));
      expect(connection.parameters.first['day'], '2026-11-03');
    });
  });

  group('PostgresH2hDrawSource', () {
    test('maps the active order and the carried members', () async {
      final order = await PostgresH2hDrawSource(
        _answers([
          [
            {'user_id': _userB},
            {'user_id': _userA},
          ],
        ]),
      ).activeOrder(monthStart: DateTime.utc(2026, 10), minActiveDays: 5);
      final carried = await PostgresH2hDrawSource(
        _answers([
          [
            {'user_id': _userA, 'next_division': 1, 'division': 2, 'rank': 3},
          ],
        ]),
      ).carriedFrom(DateTime.utc(2026, 11));

      expect((order as Ok<List<UserId>>).value, const [
        UserId(_userB),
        UserId(_userA),
      ]);
      final carry = (carried as Ok<List<H2hCarry>>).value.single;
      expect(carry.nextDivision, H2hDivision.first);
      expect(carry.division, H2hDivision.second);
      expect(carry.rank, 3);
    });
  });

  group('PostgresH2hSheetReader', () {
    test('maps members, scores and which rounds are settled or void', () async {
      final connection = _answers([
        [
          {
            'user_id': _userA,
            'slot': 0,
            'joined_at': DateTime.utc(2026, 11, 1),
          },
          {'user_id': _userB, 'slot': 1, 'joined_at': '2026-11-01T00:01:00Z'},
        ],
        [
          {
            'user_id': _userA,
            'round_no': 1,
            'points': 6,
            'exact_count': 2,
            'predicted_count': 9,
          },
        ],
        [
          {'round_no': 1, 'fixtures': 9, 'settled': 9},
          {'round_no': 2, 'fixtures': 8, 'settled': 3},
          {'round_no': 3, 'fixtures': 0, 'settled': 0},
        ],
      ]);

      final result = await PostgresH2hSheetReader(connection).sheetOf(
        leagueId: const H2hLeagueId(_league),
        rounds: const <H2hRound>[],
      );

      final sheet = (result as Ok<H2hGroupSheet>).value;
      expect(sheet.members.map((m) => m.slot).toList(), [0, 1]);
      expect(sheet.scores.single.points, 6);
      expect(sheet.scores.single.present, isTrue);
      expect(sheet.settledRounds, {1});
      expect(sheet.voidRounds, {3});
    });

    test('maps active days', () async {
      final result = await PostgresH2hSheetReader(
        _answers([
          [
            {'user_id': _userA, 'active_days': BigInt.from(12)},
          ],
        ]),
      ).activeDaysOf(DateTime.utc(2026, 11));

      expect((result as Ok<Map<UserId, int>>).value, {
        const UserId(_userA): 12,
      });
    });
  });
}
