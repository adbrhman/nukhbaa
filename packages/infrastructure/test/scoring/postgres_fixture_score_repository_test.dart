import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/scoring/postgres_fixture_score_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _fixtureA = '44444444-4444-4444-4444-444444444444';
const _participantA = '33333333-3333-3333-3333-333333333333';
const _participantB = '77777777-7777-7777-7777-777777777777';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;
  final List<Map<String, Object?>> parameters = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
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

ParticipantFixtureScore _score({
  String participantId = _participantA,
  FixtureScoreGrade grade = FixtureScoreGrade.exactScoreline,
  int points = 3,
}) =>
    (ParticipantFixtureScore.fromGraded(
              fixture: const FixtureRef(_fixtureA),
              participantId: ParticipantId(participantId),
              rulesetVersion: 1,
              result: FixtureScoreResult(
                fixture: const FixtureRef(_fixtureA),
                grade: grade,
                points: points,
              ),
            )
            as Ok<ParticipantFixtureScore>)
        .value;

void main() {
  group('PostgresFixtureScoreRepository', () {
    test(
      'saveFixtureScores is a no-op for an empty list (no query sent)',
      () async {
        final connection = _FakeConnection([
          const Result.ok(<Map<String, dynamic>>[]),
        ]);
        final repo = PostgresFixtureScoreRepository(connection);

        final result = await repo.saveFixtureScores(const []);

        expect(result, isA<Ok<void>>());
        expect(connection.parameters, isEmpty);
      },
    );

    test(
      'saveFixtureScores flattens every score into parallel arrays',
      () async {
        final connection = _FakeConnection([
          const Result.ok(<Map<String, dynamic>>[]),
        ]);
        final repo = PostgresFixtureScoreRepository(connection);

        final result = await repo.saveFixtureScores([
          _score(participantId: _participantA, points: 3),
          _score(
            participantId: _participantB,
            grade: FixtureScoreGrade.incorrect,
            points: 0,
          ),
        ]);

        expect(result, isA<Ok<void>>());
        final bound = connection.parameters.single;
        expect(bound['fixture_ids'], [_fixtureA, _fixtureA]);
        expect(bound['participant_ids'], [_participantA, _participantB]);
        expect(bound['grades'], ['exact_scoreline', 'incorrect']);
        expect(bound['points'], [3, 0]);
      },
    );

    test('listByFixture maps every row, ordered as returned', () async {
      final repo = PostgresFixtureScoreRepository(
        _FakeConnection([
          Result.ok([
            {
              'fixture_id': _fixtureA,
              'participant_id': _participantA,
              'ruleset_version': 1,
              'grade': 'exact_scoreline',
              'points': 3,
            },
            {
              'fixture_id': _fixtureA,
              'participant_id': _participantB,
              'ruleset_version': 1,
              'grade': 'pending',
              'points': 0,
            },
          ]),
        ]),
      );

      final result = await repo.listByFixture(const FixtureRef(_fixtureA));

      expect(result, isA<Ok<List<ParticipantFixtureScore>>>());
      final list = (result as Ok<List<ParticipantFixtureScore>>).value;
      expect(list, hasLength(2));
      expect(list.first.result.grade, FixtureScoreGrade.exactScoreline);
      expect(list.last.result.grade, FixtureScoreGrade.pending);
    });

    test('an empty result maps to an empty list', () async {
      final repo = PostgresFixtureScoreRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final result = await repo.listByFixture(const FixtureRef(_fixtureA));
      expect((result as Ok<List<ParticipantFixtureScore>>).value, isEmpty);
    });

    test('an unparseable grade surfaces as row_corrupt', () async {
      final repo = PostgresFixtureScoreRepository(
        _FakeConnection([
          Result.ok([
            {
              'fixture_id': _fixtureA,
              'participant_id': _participantA,
              'ruleset_version': 1,
              'grade': 'not_a_real_grade',
              'points': 0,
            },
          ]),
        ]),
      );
      final result = await repo.listByFixture(const FixtureRef(_fixtureA));
      expect(result, isA<Err<List<ParticipantFixtureScore>>>());
      expect(
        (result as Err<List<ParticipantFixtureScore>>).error.code,
        'scoring.row_corrupt',
      );
    });

    test('a transient connection error passes through verbatim', () async {
      const error = AppError.transient('boom', 'db down');
      final repo = PostgresFixtureScoreRepository(
        _FakeConnection([const Result.err(error)]),
      );
      final result = await repo.listByFixture(const FixtureRef(_fixtureA));
      expect((result as Err<List<ParticipantFixtureScore>>).error.code, 'boom');
    });
  });
}
