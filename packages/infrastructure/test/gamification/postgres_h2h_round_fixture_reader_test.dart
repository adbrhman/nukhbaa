import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_round_fixture_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _round = '22222222-2222-4222-8222-222222222222';
const _me = UserId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
const _them = UserId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
const _f1 = 'f1000000-0000-4000-8000-000000000001';
const _f2 = 'f2000000-0000-4000-8000-000000000002';

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself is exercised end to end by
/// `supabase/tests/0100_h2h_round_fixtures_queries_test.sql`.
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

H2hRound _h2hRound({required bool locked}) => H2hRound(
  id: const H2hRoundId(_round),
  monthStart: DateTime.utc(2026, 11),
  number: 2,
  day: DateTime.utc(2026, 11, 3),
  fixtureCount: 2,
  approvedBy: null,
  lockedAt: locked ? DateTime.utc(2026, 11, 3, 12) : null,
);

Map<String, dynamic> _fixtureRow(
  String id,
  Object? kickoff, {
  bool counted = true,
  int? home,
  int? away,
}) => {
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

void main() {
  group('PostgresH2hRoundFixtureReader', () {
    test('a round with no fixture asks nothing more', () async {
      final connection = _answers([<Map<String, dynamic>>[]]);

      final result = await PostgresH2hRoundFixtureReader(connection).fixturesOf(
        round: _h2hRound(locked: false),
        reader: _me,
        opponent: _them,
        nowUtc: DateTime.utc(2026, 11, 3, 9),
      );

      expect((result as Ok<List<H2hRoundFixture>>).value, isEmpty);
      expect(connection.sqls, hasLength(1));
      expect(connection.parameters.single, {
        'locked': false,
        'round_id': _round,
        'day': '2026-11-03',
      });
    });

    test('maps the fixtures and folds each player\'s participations', () async {
      final connection = _answers([
        [
          _fixtureRow(_f1, DateTime.utc(2026, 11, 3, 12), home: 2, away: 1),
          _fixtureRow(_f2, '2026-11-03T15:00:00Z', counted: false),
        ],
        [
          // Two participations of mine on f1: the first pick is kept, the
          // points add up, exact when either says so.
          _pickRow(_me, _f1, 2, 1, isDouble: true, points: 6, exact: true),
          _pickRow(_me, _f1, 0, 0, points: BigInt.from(1)),
          _pickRow(_me, _f2, 1, 1),
          _pickRow(_them, _f1, 1, 0, points: 3),
        ],
      ]);
      final now = DateTime.utc(2026, 11, 3, 13);

      final result = await PostgresH2hRoundFixtureReader(connection).fixturesOf(
        round: _h2hRound(locked: true),
        reader: _me,
        opponent: _them,
        nowUtc: now,
      );

      final fixtures = (result as Ok<List<H2hRoundFixture>>).value;
      expect(fixtures.map((f) => f.fixtureId).toList(), [_f1, _f2]);

      final f1 = fixtures[0];
      expect(f1.homeTeam, 'Home $_f1');
      expect(f1.homeTeamId, isNull);
      expect(f1.awayTeamId, 'team-away');
      expect(f1.kickoffAt, DateTime.utc(2026, 11, 3, 12));
      expect(f1.counted, isTrue);
      expect((f1.homeGoals, f1.awayGoals), (2, 1));
      expect(f1.mine!.homeGoals, 2);
      expect(f1.mine!.isDouble, isTrue);
      expect(f1.mine!.points, 7);
      expect(f1.mine!.exact, isTrue);
      expect(f1.theirs!.homeGoals, 1);
      expect(f1.theirs!.points, 3);

      final f2 = fixtures[1];
      expect(f2.counted, isFalse);
      expect(f2.kickoffAt, DateTime.utc(2026, 11, 3, 15));
      expect(f2.homeGoals, isNull);
      expect(f2.mine!.points, isNull, reason: 'no final score yet');
      expect(f2.theirs, isNull);

      expect(connection.parameters[0]['locked'], isTrue);
      expect(connection.parameters[1], {
        'fixture_ids': '$_f1,$_f2',
        'reader': _me.value,
        'opponent': _them.value,
        'now': now,
      });
    });

    test('with the group average no opponent is asked for', () async {
      final connection = _answers([
        [_fixtureRow(_f1, DateTime.utc(2026, 11, 3, 12))],
        [_pickRow(_me, _f1, 1, 0)],
      ]);

      final result = await PostgresH2hRoundFixtureReader(connection).fixturesOf(
        round: _h2hRound(locked: true),
        reader: _me,
        opponent: null,
        nowUtc: DateTime.utc(2026, 11, 3, 13),
      );

      final fixture = (result as Ok<List<H2hRoundFixture>>).value.single;
      expect(fixture.mine!.homeGoals, 1);
      expect(fixture.theirs, isNull);
      expect(connection.parameters[1]['opponent'], isNull);
    });

    test('a fixture row without an id is an error, not a guess', () async {
      final result =
          await PostgresH2hRoundFixtureReader(
            _answers([
              [_fixtureRow('', DateTime.utc(2026, 11, 3, 12))],
            ]),
          ).fixturesOf(
            round: _h2hRound(locked: true),
            reader: _me,
            opponent: _them,
            nowUtc: DateTime.utc(2026, 11, 3, 13),
          );

      expect(
        (result as Err<List<H2hRoundFixture>>).error.code,
        'gamification.h2h_row_corrupt',
      );
    });

    test('a failing connection is passed on', () async {
      final result =
          await PostgresH2hRoundFixtureReader(
            _FakeConnection([
              const Result.err(AppError.transient('db.down', 'down')),
            ]),
          ).fixturesOf(
            round: _h2hRound(locked: false),
            reader: _me,
            opponent: _them,
            nowUtc: DateTime.utc(2026, 11, 3, 13),
          );

      expect((result as Err<List<H2hRoundFixture>>).error.code, 'db.down');
    });
  });
}
