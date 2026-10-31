import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_h2h_cup_store.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _stage = 'c1900000-0000-4000-8000-0000000005a1';
const _u1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _u2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

/// Answers each query with the next scripted response, recording what was
/// asked. The SQL itself is exercised end to end by
/// `supabase/tests/0190_h2h_elite_cup_test.sql`.
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
  test('stateOf reads entries, stages with their pairs and results, and '
      'titles', () async {
    final connection = _answers([
      [
        {
          'user_id': _u1,
          'place': 1,
          'group_number': 2,
          'league_points': 40,
          'points_for': 120,
          'exact_count': 9,
        },
      ],
      [
        {
          'stage_id': _stage,
          'slot': 1,
          'home_user': _u1,
          'away_user': _u2,
          'outcome': 'points',
          'winner_user': _u1,
          'home_points': 9,
          'away_points': 4,
          'home_exact': 1,
          'away_exact': 0,
          'home_predicted': 8,
          'away_predicted': 6,
        },
      ],
      [
        {
          'id': _stage,
          'place': 1,
          'stage': 'semi',
          'attempt': 1,
          'day': '2026-11-20',
          'fixture_count': 9,
          'locked_at': DateTime.utc(2026, 11, 20, 15),
        },
      ],
      [
        {'place': 1, 'champion': _u1, 'runner_up': _u2, 'how': 'final'},
      ],
    ]);

    final result = await PostgresH2hCupStore(
      connection,
    ).stateOf(DateTime.utc(2026, 11));

    final state = (result as Ok<H2hCupState>).value;
    expect(connection.parameters.first, {'month': '2026-11-01'});
    expect(state.entries.single.groupNumber, 2);
    final stage = state.stages.single;
    expect(stage.step, const H2hCupStep(1, H2hCupRound.semi));
    expect(stage.day, DateTime.utc(2026, 11, 20));
    expect(stage.locked, isTrue);
    expect(stage.pairs.single.away, const UserId(_u2));
    expect(stage.results.single.winner, const UserId(_u1));
    expect(stage.results.single.home.points, 9);
    expect(stage.decided, isTrue);
    expect(state.titleOf(1)!.champion, const UserId(_u1));
  });

  test('a stage with an unknown round is a corrupt row', () async {
    final connection = _answers([
      [],
      [],
      [
        {
          'id': _stage,
          'place': 1,
          'stage': 'quarter',
          'attempt': 1,
          'day': '2026-11-20',
          'fixture_count': 9,
          'locked_at': null,
        },
      ],
      [],
    ]);

    final result = await PostgresH2hCupStore(
      connection,
    ).stateOf(DateTime.utc(2026, 11));

    expect(result, isA<Err<H2hCupState>>());
  });

  test('schedule writes the stage then its pairs, with their values', () async {
    final connection = _answers([[]]);

    final result = await PostgresH2hCupStore(connection).schedule(
      id: const H2hCupStageId(_stage),
      monthStart: DateTime.utc(2026, 11),
      step: const H2hCupStep(2, H2hCupRound.finale),
      attempt: 2,
      day: DateTime.utc(2026, 11, 23),
      fixtureCount: 7,
      pairs: const [H2hCupPair(slot: 1, home: UserId(_u1), away: UserId(_u2))],
    );

    expect(result, isA<Ok<void>>());
    expect(connection.sqls, [
      PostgresH2hCupStore.stageSql,
      PostgresH2hCupStore.pairSql,
    ]);
    expect(connection.parameters.first, {
      'id': _stage,
      'month': '2026-11-01',
      'place': 2,
      'stage': 'final',
      'attempt': 2,
      'day': '2026-11-23',
      'fixture_count': 7,
    });
    expect(connection.parameters.last, {
      'stage_id': _stage,
      'slot': 1,
      'home': _u1,
      'away': _u2,
    });
  });

  test('figuresOf reads the counts and every side', () async {
    final connection = _answers([
      [
        {'fixtures': 8, 'settled': 8},
      ],
      [
        {'user_id': _u1, 'points': 12, 'exact_count': 2, 'predicted_count': 8},
        {'user_id': _u2, 'points': 0, 'exact_count': 0, 'predicted_count': 0},
      ],
    ]);

    final result = await PostgresH2hCupStore(
      connection,
    ).figuresOf(const H2hCupStageId(_stage));

    final figures = (result as Ok<H2hCupStageFigures>).value;
    expect(figures.judged, isTrue);
    expect(figures.sideOf(const UserId(_u1)).points, 12);
    expect(figures.sideOf(const UserId(_u2)).present, isFalse);
  });

  test('decide and crown bind every value; a failure is returned', () async {
    final connection = _answers([[]]);
    final store = PostgresH2hCupStore(connection);

    await store.decide(
      stageId: const H2hCupStageId(_stage),
      results: const [
        H2hCupResult(
          slot: 2,
          winner: null,
          outcome: 'both_absent',
          home: H2hCupSide.absent,
          away: H2hCupSide.absent,
        ),
      ],
    );
    await store.crown(
      monthStart: DateTime.utc(2026, 11),
      place: 3,
      champion: null,
      runnerUp: null,
      how: 'vacant',
    );

    expect(connection.parameters.first['winner'], isNull);
    expect(connection.parameters.first['outcome'], 'both_absent');
    expect(connection.parameters.last, {
      'month': '2026-11-01',
      'place': 3,
      'champion': null,
      'runner_up': null,
      'how': 'vacant',
    });

    final failing = PostgresH2hCupStore(
      _FakeConnection([
        const Result.err(AppError.transient('db.down', 'Database down')),
      ]),
    );
    expect(
      await failing.crown(
        monthStart: DateTime.utc(2026, 11),
        place: 1,
        champion: null,
        runnerUp: null,
        how: 'vacant',
      ),
      isA<Err<void>>(),
    );
  });
}
