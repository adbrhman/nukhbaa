import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_control_store.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_month_report_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _admin = UserId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself is exercised end to end by
/// `supabase/tests/0101_h2h_control_queries_test.sql`.
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
  group('PostgresH2hControlStore', () {
    test('reads the settings row', () async {
      final result = await PostgresH2hControlStore(
        _answers([
          [
            {
              'auto_approve': false,
              'lead_hours': 6,
              'min_active_days': BigInt.from(3),
              'updated_by': _admin.value,
              'updated_at': DateTime.utc(2026, 10, 10, 9),
            },
          ],
        ]),
      ).settings();

      final settings = (result as Ok<H2hSettings>).value;
      expect(settings.autoApprove, isFalse);
      expect(settings.leadHours, 6);
      expect(settings.minActiveDays, 3);
      expect(settings.updatedBy, _admin);
      expect(settings.updatedAt, DateTime.utc(2026, 10, 10, 9));
    });

    test('without the row, the rules of 0100 stand', () async {
      final result = await PostgresH2hControlStore(
        _answers([<Map<String, dynamic>>[]]),
      ).settings();

      final settings = (result as Ok<H2hSettings>).value;
      expect(settings.autoApprove, isTrue);
      expect(settings.leadHours, 24);
      expect(settings.minActiveDays, H2hLeaguePolicy.minActiveDays);
    });

    test('saves the settings with who did it', () async {
      final connection = _answers([<Map<String, dynamic>>[]]);

      final result = await PostgresH2hControlStore(connection).saveSettings(
        autoApprove: true,
        leadHours: 12,
        minActiveDays: 4,
        by: _admin,
      );

      expect(result, isA<Ok<void>>());
      expect(connection.parameters.single, {
        'auto_approve': true,
        'lead_hours': 12,
        'min_active_days': 4,
        'updated_by': _admin.value,
      });
    });

    test('excluded days, and whether an exclusion was new', () async {
      final connection = _answers([
        [
          {'day': '2026-11-05'},
          {'day': '2026-11-09'},
        ],
        [
          {'excluded': 1},
        ],
        <Map<String, dynamic>>[],
      ]);
      final store = PostgresH2hControlStore(connection);

      final days = await store.excludedDays(
        from: DateTime.utc(2026, 11),
        through: DateTime.utc(2026, 11, 30),
      );
      final fresh = await store.exclude(
        day: DateTime.utc(2026, 11, 7),
        by: _admin,
      );
      final lifted = await store.include(DateTime.utc(2026, 11, 7));

      expect((days as Ok<Set<DateTime>>).value, {
        DateTime.utc(2026, 11, 5),
        DateTime.utc(2026, 11, 9),
      });
      expect((fresh as Ok<bool>).value, isTrue);
      expect((lifted as Ok<bool>).value, isFalse);
      expect(connection.parameters[0], {
        'from_day': '2026-11-01',
        'through_day': '2026-11-30',
      });
      expect(connection.parameters[1]['day'], '2026-11-07');
    });

    test('a late seat is inserted with its group, month and slot', () async {
      final connection = _answers([<Map<String, dynamic>>[]]);

      final result = await PostgresH2hControlStore(connection).addSeat(
        leagueId: const H2hLeagueId('11111111-1111-4111-8111-111111111111'),
        monthStart: DateTime.utc(2026, 11),
        userId: _admin,
        slot: 3,
      );

      expect(result, isA<Ok<void>>());
      expect(connection.parameters.single, {
        'league_id': '11111111-1111-4111-8111-111111111111',
        'month': '2026-11-01',
        'user_id': _admin.value,
        'slot': 3,
      });
    });

    test('the log: written as JSON, read back newest first', () async {
      final connection = _answers([
        <Map<String, dynamic>>[],
        [
          {
            'id': 'a-2',
            'action': 'day_excluded',
            'actor': _admin.value,
            'detail': '{"day":"2026-11-05"}',
            'acted_at': DateTime.utc(2026, 10, 10, 10),
          },
          {
            'id': 'a-1',
            'action': 'something_newer',
            'actor': null,
            'detail': '{}',
            'acted_at': DateTime.utc(2026, 10, 10, 9),
          },
        ],
      ]);
      final store = PostgresH2hControlStore(connection);

      await store.record(
        id: 'a-2',
        action: H2hAdminActionKind.dayExcluded,
        by: _admin,
        detail: const {'day': '2026-11-05'},
      );
      final result = await store.recentActions(20);

      expect(connection.parameters[0]['action'], 'day_excluded');
      expect(connection.parameters[0]['detail'], '{"day":"2026-11-05"}');
      final actions = (result as Ok<List<H2hAdminAction>>).value;
      // A kind this build does not know is left out.
      expect(actions, hasLength(1));
      expect(actions.single.action, H2hAdminActionKind.dayExcluded);
      expect(actions.single.detail, {'day': '2026-11-05'});
      expect(actions.single.actor, _admin);
    });
  });

  group('PostgresH2hMonthReportReader', () {
    test('reads the counts of a closed month', () async {
      final result = await PostgresH2hMonthReportReader(
        _answers([
          [
            {
              'drawn_at': DateTime.utc(2026, 10, 31, 21, 5),
              'is_pilot': false,
              'drawn_seats': 62,
              'seats': BigInt.from(63),
              'groups': '1:1,2:1,3:1,4:1',
              'closed_at': DateTime.utc(2026, 11, 30, 21, 10),
              'closed_members': 63,
              'outcomes': 'held:51,out:3,promoted:5,relegated:4',
            },
          ],
        ]),
      ).reportOf(DateTime.utc(2026, 11, 17));

      final report = (result as Ok<H2hMonthReport>).value;
      expect(report.monthStart, DateTime.utc(2026, 11));
      expect(report.drawnSeats, 62);
      expect(report.seats, 63);
      expect(report.groupsByDivision, {1: 1, 2: 1, 3: 1, 4: 1});
      expect(report.closedMembers, 63);
      expect(report.outcomes['promoted'], 5);
      expect(report.outcomes['out'], 3);
    });

    test('a month never drawn reads as empty', () async {
      final result = await PostgresH2hMonthReportReader(
        _answers([
          [
            {
              'drawn_at': null,
              'is_pilot': false,
              'drawn_seats': 0,
              'seats': 0,
              'groups': '',
              'closed_at': null,
              'closed_members': 0,
              'outcomes': '',
            },
          ],
        ]),
      ).reportOf(DateTime.utc(2026, 12));

      final report = (result as Ok<H2hMonthReport>).value;
      expect(report.drawnAt, isNull);
      expect(report.groupsByDivision, isEmpty);
      expect(report.outcomes, isEmpty);
    });

    test('an unreadable count is an error, not a guess', () async {
      final result = await PostgresH2hMonthReportReader(
        _answers([
          [
            {
              'drawn_at': null,
              'is_pilot': false,
              'drawn_seats': 0,
              'seats': 0,
              'groups': 'garbage',
              'closed_at': null,
              'closed_members': 0,
              'outcomes': '',
            },
          ],
        ]),
      ).reportOf(DateTime.utc(2026, 12));

      expect(
        (result as Err<H2hMonthReport>).error.code,
        'gamification.h2h_row_corrupt',
      );
    });
  });
}
