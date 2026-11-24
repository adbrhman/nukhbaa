// NK311_02
import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_cup_pick_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _stageA = H2hCupStageId('55555555-5555-4555-8555-555555555551');
const _stageB = H2hCupStageId('55555555-5555-4555-8555-555555555552');
const _u1 = UserId('00000000-0000-4000-9000-000000000001');
const _u2 = UserId('00000000-0000-4000-9000-000000000002');
const _u3 = UserId('00000000-0000-4000-9000-000000000003');
const _u4 = UserId('00000000-0000-4000-9000-000000000004');
const _f1 = 'f1000000-0000-4000-8000-000000000001';
const _f2 = 'f2000000-0000-4000-8000-000000000002';

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself is exercised end to end by the database tests.
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

H2hCupStage _stage(
  H2hCupStageId id,
  UserId home,
  UserId away, {
  int place = 1,
}) => H2hCupStage(
  id: id,
  monthStart: DateTime.utc(2026, 11),
  step: H2hCupStep(place, H2hCupRound.semi),
  attempt: 1,
  day: DateTime.utc(2026, 11, 22),
  fixtureCount: 2,
  lockedAt: DateTime.utc(2026, 11, 22, 9),
  pairs: [H2hCupPair(slot: 1, home: home, away: away)],
  results: const <H2hCupResult>[],
);

Map<String, dynamic> _fixtureRow(
  H2hCupStageId stage,
  String id,
  Object? kickoff, {
  bool counted = true,
  Object? home,
  Object? away,
}) => {
  'stage_id': stage.value,
  'fixture_id': id,
  'home_team': 'Home $id',
  'away_team': 'Away $id',
  'home_team_id': null,
  'away_team_id': 'team-away',
  'kickoff_at': kickoff,
  'counted': counted,
  'home_goals': home,
  'away_goals': away,
};

Map<String, dynamic> _pickRow(
  UserId user,
  String fixture,
  int home,
  int away, {
  bool isDouble = false,
  Object? points,
  bool exact = false,
}) => {
  'user_id': user.value,
  'fixture_id': fixture,
  'home_goals': home,
  'away_goals': away,
  'is_double': isDouble,
  'points': points,
  'exact': exact,
};

final _now = DateTime.utc(2026, 11, 22, 13);

void main() {
  group('PostgresH2hCupPickReader: the statements', () {
    test('the player statement withholds another player before kickoff', () {
      const sql = PostgresH2hCupPickReader.maskedPicksSql;

      expect(sql, contains('p.user_id = @reader::uuid'));
      expect(sql, contains('fs.kickoff_at <= @now::timestamptz'));
      expect(sql, contains("u.status <> 'suspended'"));
      expect(sql, contains('ORDER BY p.user_id, fp.fixture_id'));
    });

    test('the owners statement withholds nothing and takes no reader', () {
      const sql = PostgresH2hCupPickReader.unmaskedPicksSql;

      expect(sql, isNot(contains('@reader')));
      expect(sql, isNot(contains('@now')));
      expect(sql, isNot(contains('kickoff_at')));
      expect(sql, contains("u.status <> 'suspended'"));
      expect(sql, contains('ORDER BY p.user_id, fp.fixture_id'));
    });

    test('both pick statements read the same rows apart from the mask', () {
      const masked = PostgresH2hCupPickReader.maskedPicksSql;
      const unmasked = PostgresH2hCupPickReader.unmaskedPicksSql;
      final cut = masked.indexOf('  AND (p.user_id = @reader');
      final end = masked.indexOf('ORDER BY');

      expect(cut, greaterThan(0));
      expect(masked.substring(0, cut) + masked.substring(end), unmasked);
    });

    test('a stage is frozen by its lock row, not by a parameter', () {
      const sql = PostgresH2hCupPickReader.fixturesSql;

      expect(sql, contains('gamification.h2h_cup_stage_locks'));
      expect(sql, contains('gamification.h2h_cup_stage_fixtures'));
      expect(sql, contains('WHERE NOT st.locked'));
      expect(sql, contains('@stage_ids::text'));
    });
  });

  group('PostgresH2hCupPickReader: the player way in', () {
    test(
      'maps the fixtures of each stage and the picks of its players',
      () async {
        final connection = _answers([
          [
            _fixtureRow(
              _stageA,
              _f1,
              DateTime.utc(2026, 11, 22, 12),
              home: 2,
              away: BigInt.from(1),
            ),
            _fixtureRow(_stageA, _f2, '2026-11-22T15:00:00Z', counted: false),
            _fixtureRow(_stageB, _f1, DateTime.utc(2026, 11, 22, 12)),
          ],
          [
            _pickRow(_u1, _f1, 2, 1, isDouble: true, points: 6, exact: true),
            _pickRow(_u1, _f1, 0, 0, points: BigInt.from(1)),
            _pickRow(_u2, _f1, 1, 0, points: 3),
            _pickRow(_u3, _f1, 4, 4),
            _pickRow(_u4, _f1, 5, 5),
            _pickRow(_u1, _f2, 1, 1),
          ],
        ]);

        final result = await PostgresH2hCupPickReader(connection).fixturesOf(
          stages: [
            _stage(_stageA, _u1, _u2),
            _stage(_stageB, _u3, _u4, place: 2),
          ],
          reader: _u1,
          nowUtc: _now,
        );

        final byStage =
            (result as Ok<Map<H2hCupStageId, List<H2hCupStageFixture>>>).value;
        final a = byStage[_stageA]!;
        expect(a.map((f) => f.fixtureId), [_f1, _f2]);
        expect(a[0].homeTeam, 'Home $_f1');
        expect(a[0].homeTeamId, isNull);
        expect(a[0].awayTeamId, 'team-away');
        expect(a[0].kickoffAt, DateTime.utc(2026, 11, 22, 12));
        expect(a[0].counted, isTrue);
        expect((a[0].homeGoals, a[0].awayGoals), (2, 1));
        expect(a[0].picks.keys.toSet(), {_u1, _u2});
        final mine = a[0].picks[_u1]!;
        expect(mine.homeGoals, 2);
        expect(mine.isDouble, isTrue);
        expect(mine.points, 7);
        expect(mine.exact, isTrue);
        expect(a[0].picks[_u2]!.points, 3);
        expect(a[1].counted, isFalse);
        expect(a[1].kickoffAt, DateTime.utc(2026, 11, 22, 15));
        expect(a[1].homeGoals, isNull);
        expect(a[1].picks.keys.toSet(), {_u1});
        expect(a[1].picks[_u1]!.points, isNull);

        // The fixture both stages hold gives each stage its own players only.
        final b = byStage[_stageB]!.single;
        expect(b.picks.keys.toSet(), {_u3, _u4});
      },
    );

    test('asks once for the stages and once, masked, for the picks', () async {
      final connection = _answers([
        [
          _fixtureRow(_stageA, _f1, DateTime.utc(2026, 11, 22, 12)),
          _fixtureRow(_stageB, _f2, DateTime.utc(2026, 11, 22, 18)),
        ],
        <Map<String, dynamic>>[],
      ]);

      await PostgresH2hCupPickReader(connection).fixturesOf(
        stages: [
          _stage(_stageA, _u1, _u2),
          _stage(_stageB, _u3, _u4, place: 2),
        ],
        reader: _u1,
        nowUtc: _now,
      );

      expect(connection.sqls, [
        PostgresH2hCupPickReader.fixturesSql,
        PostgresH2hCupPickReader.maskedPicksSql,
      ]);
      expect(connection.parameters[0], {
        'stage_ids': '${_stageA.value},${_stageB.value}',
      });
      expect(connection.parameters[1], {
        'fixture_ids': '$_f1,$_f2',
        'players': '${_u1.value},${_u2.value},${_u3.value},${_u4.value}',
        'reader': _u1.value,
        'now': _now,
      });
    });

    test('the server clock is passed in UTC', () async {
      final connection = _answers([
        [_fixtureRow(_stageA, _f1, DateTime.utc(2026, 11, 22, 12))],
        <Map<String, dynamic>>[],
      ]);

      await PostgresH2hCupPickReader(connection).fixturesOf(
        stages: [_stage(_stageA, _u1, _u2)],
        reader: _u1,
        nowUtc: DateTime.parse('2026-11-22T16:00:00+03:00'),
      );

      final sent = connection.parameters[1]['now']! as DateTime;
      expect(sent.isUtc, isTrue);
      expect(sent, DateTime.utc(2026, 11, 22, 13));
    });
  });

  group('PostgresH2hCupPickReader: the owners way in', () {
    test('runs the unmasked statement and sends no reader or clock', () async {
      final connection = _answers([
        [_fixtureRow(_stageA, _f1, DateTime.utc(2026, 11, 23, 12))],
        [_pickRow(_u1, _f1, 2, 1), _pickRow(_u2, _f1, 0, 0)],
      ]);

      final result = await PostgresH2hCupPickReader(
        connection,
      ).fixturesOfUnmasked(stages: [_stage(_stageA, _u1, _u2)]);

      final fixture =
          (result as Ok<Map<H2hCupStageId, List<H2hCupStageFixture>>>)
              .value[_stageA]!
              .single;
      expect(fixture.picks.keys.toSet(), {_u1, _u2});
      expect(connection.sqls, [
        PostgresH2hCupPickReader.fixturesSql,
        PostgresH2hCupPickReader.unmaskedPicksSql,
      ]);
      expect(connection.parameters[1], {
        'fixture_ids': _f1,
        'players': '${_u1.value},${_u2.value}',
      });
    });
  });

  group('PostgresH2hCupPickReader: nothing to read', () {
    test('no stage asks nothing', () async {
      final connection = _answers([<Map<String, dynamic>>[]]);

      final result = await PostgresH2hCupPickReader(
        connection,
      ).fixturesOf(stages: const <H2hCupStage>[], reader: _u1, nowUtc: _now);

      expect(
        (result as Ok<Map<H2hCupStageId, List<H2hCupStageFixture>>>).value,
        isEmpty,
      );
      expect(connection.sqls, isEmpty);
    });

    test(
      'a stage with no fixture maps to none and asks for no picks',
      () async {
        final connection = _answers([<Map<String, dynamic>>[]]);

        final result = await PostgresH2hCupPickReader(connection).fixturesOf(
          stages: [_stage(_stageA, _u1, _u2)],
          reader: _u1,
          nowUtc: _now,
        );

        final byStage =
            (result as Ok<Map<H2hCupStageId, List<H2hCupStageFixture>>>).value;
        expect(byStage[_stageA], isEmpty);
        expect(connection.sqls, hasLength(1));
      },
    );
  });

  group('PostgresH2hCupPickReader: failures', () {
    test('a fixture row without an id is an error, not a guess', () async {
      final result =
          await PostgresH2hCupPickReader(
            _answers([
              [_fixtureRow(_stageA, '', DateTime.utc(2026, 11, 22, 12))],
            ]),
          ).fixturesOf(
            stages: [_stage(_stageA, _u1, _u2)],
            reader: _u1,
            nowUtc: _now,
          );

      expect(
        (result as Err<Map<H2hCupStageId, List<H2hCupStageFixture>>>)
            .error
            .code,
        'gamification.h2h_row_corrupt',
      );
    });

    test('a prediction row without goals is an error, not a guess', () async {
      final result =
          await PostgresH2hCupPickReader(
            _answers([
              [_fixtureRow(_stageA, _f1, DateTime.utc(2026, 11, 22, 12))],
              [
                {..._pickRow(_u1, _f1, 1, 0), 'home_goals': null},
              ],
            ]),
          ).fixturesOf(
            stages: [_stage(_stageA, _u1, _u2)],
            reader: _u1,
            nowUtc: _now,
          );

      expect(
        (result as Err<Map<H2hCupStageId, List<H2hCupStageFixture>>>)
            .error
            .code,
        'gamification.h2h_row_corrupt',
      );
    });

    test('a failing connection is passed on, at either query', () async {
      final down = const Result<List<Map<String, dynamic>>>.err(
        AppError.transient('db.down', 'down'),
      );

      final first = await PostgresH2hCupPickReader(_FakeConnection([down]))
          .fixturesOf(
            stages: [_stage(_stageA, _u1, _u2)],
            reader: _u1,
            nowUtc: _now,
          );
      final second = await PostgresH2hCupPickReader(
        _FakeConnection([
          Result.ok([
            _fixtureRow(_stageA, _f1, DateTime.utc(2026, 11, 22, 12)),
          ]),
          down,
        ]),
      ).fixturesOfUnmasked(stages: [_stage(_stageA, _u1, _u2)]);

      expect(
        (first as Err<Map<H2hCupStageId, List<H2hCupStageFixture>>>).error.code,
        'db.down',
      );
      expect(
        (second as Err<Map<H2hCupStageId, List<H2hCupStageFixture>>>)
            .error
            .code,
        'db.down',
      );
    });
  });
}
