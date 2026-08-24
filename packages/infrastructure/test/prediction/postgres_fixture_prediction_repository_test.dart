import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/prediction/postgres_fixture_prediction_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _predictionId = '11111111-1111-1111-1111-111111111111';
const _seasonId = '22222222-2222-2222-2222-222222222222';
const _participantId = '33333333-3333-3333-3333-333333333333';
const _fixtureA = '44444444-4444-4444-4444-444444444444';
const _fixtureB = '55555555-5555-5555-5555-555555555555';

/// Fake [PostgresConnection] replaying a scripted queue of [Result]s (one per
/// `query`) — same double used by `postgres_prediction_repository_test.dart`.
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

Map<String, dynamic> _row({
  String id = _predictionId,
  String fixtureId = _fixtureA,
  String participantId = _participantId,
  int homeGoals = 2,
  int awayGoals = 1,
  bool isDouble = false,
  DateTime? submittedAt,
}) => {
  'id': id,
  'fixture_id': fixtureId,
  'participant_id': participantId,
  'home_goals': homeGoals,
  'away_goals': awayGoals,
  'is_double': isDouble,
  'submitted_at': (submittedAt ?? DateTime.utc(2026, 8, 1)).toIso8601String(),
};

void main() {
  group('PostgresFixturePredictionRepository', () {
    test('findByFixtureAndParticipant returns Ok(null) when absent', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final result = await repo.findByFixtureAndParticipant(
        const FixtureRef(_fixtureA),
        const ParticipantId(_participantId),
      );
      expect(result, isA<Ok<FixturePredictionView?>>());
      expect((result as Ok<FixturePredictionView?>).value, isNull);
    });

    test('findByFixtureAndParticipant maps a found row', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([
          Result.ok([_row()]),
        ]),
      );
      final result = await repo.findByFixtureAndParticipant(
        const FixtureRef(_fixtureA),
        const ParticipantId(_participantId),
      );
      final view = (result as Ok<FixturePredictionView?>).value!;
      expect(view.prediction.homeGoals, 2);
      expect(view.prediction.awayGoals, 1);
      expect(view.prediction.fixture, const FixtureRef(_fixtureA));
    });

    test(
      'save binds every field, including submitted_at as UTC ISO-8601',
      () async {
        final connection = _FakeConnection([
          const Result.ok(<Map<String, dynamic>>[]),
        ]);
        final repo = PostgresFixturePredictionRepository(connection);
        final prediction =
            (FixturePrediction.submit(
                      id: const PredictionId(_predictionId),
                      fixture: const FixtureRef(_fixtureA),
                      participantId: const ParticipantId(_participantId),
                      lock:
                          (FixtureLock.at(
                                    kickoffAt: DateTime.utc(2026, 8, 2),
                                    nowUtc: DateTime.utc(2026, 8, 1),
                                  )
                                  as Ok<FixtureLock>)
                              .value,
                      homeGoals: 2,
                      awayGoals: 1,
                    )
                    as Ok<FixturePrediction>)
                .value;

        final result = await repo.save(
          prediction,
          DateTime.utc(2026, 8, 1, 12),
        );

        expect(result, isA<Ok<void>>());
        expect(connection.parameters.single['id'], _predictionId);
        expect(connection.parameters.single['fixture_id'], _fixtureA);
        expect(
          connection.parameters.single['submitted_at'],
          '2026-08-01T12:00:00.000Z',
        );
      },
    );

    test(
      'update surfaces prediction.not_found on an empty RETURNING',
      () async {
        final repo = PostgresFixturePredictionRepository(
          _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
        );
        final prediction =
            (FixturePrediction.submit(
                      id: const PredictionId(_predictionId),
                      fixture: const FixtureRef(_fixtureA),
                      participantId: const ParticipantId(_participantId),
                      lock:
                          (FixtureLock.at(
                                    kickoffAt: DateTime.utc(2026, 8, 2),
                                    nowUtc: DateTime.utc(2026, 8, 1),
                                  )
                                  as Ok<FixtureLock>)
                              .value,
                      homeGoals: 0,
                      awayGoals: 0,
                    )
                    as Ok<FixturePrediction>)
                .value;

        final result = await repo.update(prediction, DateTime.utc(2026, 8, 1));

        expect(result, isA<Err<void>>());
        expect((result as Err<void>).error.code, 'prediction.not_found');
      },
    );

    test('findSeasonFixture returns Ok(null) when not linked', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final result = await repo.findSeasonFixture(
        const SeasonId(_seasonId),
        const FixtureRef(_fixtureA),
      );
      expect(result, isA<Ok<SeasonFixture?>>());
      expect((result as Ok<SeasonFixture?>).value, isNull);
    });

    test('findSeasonFixture maps a linked row', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([
          Result.ok([
            {
              'season_id': _seasonId,
              'fixture_id': _fixtureA,
              'display_order': 3,
            },
          ]),
        ]),
      );
      final result = await repo.findSeasonFixture(
        const SeasonId(_seasonId),
        const FixtureRef(_fixtureA),
      );
      final link = (result as Ok<SeasonFixture?>).value!;
      expect(link.displayOrder, 3);
    });

    test('countDoublesOnDay maps the count column', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([
          Result.ok([
            {'n': 2},
          ]),
        ]),
      );
      final result = await repo.countDoublesOnDay(
        const ParticipantId(_participantId),
        DateTime.utc(2026, 8, 1),
      );
      expect(result, isA<Ok<int>>());
      expect((result as Ok<int>).value, 2);
    });

    test('countDoublesOnDay defaults to 0 on an empty result', () async {
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.ok(<Map<String, dynamic>>[])]),
      );
      final result = await repo.countDoublesOnDay(
        const ParticipantId(_participantId),
        DateTime.utc(2026, 8, 1),
      );
      expect((result as Ok<int>).value, 0);
    });

    test(
      'listByFixture groups by first-seen order, no grouping needed (flat rows)',
      () async {
        final repo = PostgresFixturePredictionRepository(
          _FakeConnection([
            Result.ok([
              _row(participantId: _participantId, fixtureId: _fixtureB),
              _row(
                id: '66666666-6666-6666-6666-666666666666',
                participantId: '77777777-7777-7777-7777-777777777777',
                fixtureId: _fixtureB,
              ),
            ]),
          ]),
        );
        final result = await repo.listByFixture(const FixtureRef(_fixtureB));
        expect(result, isA<Ok<List<FixturePredictionView>>>());
        expect((result as Ok<List<FixturePredictionView>>).value, hasLength(2));
      },
    );

    test(
      'a corrupt row (non-integer home_goals) surfaces as row_corrupt',
      () async {
        final repo = PostgresFixturePredictionRepository(
          _FakeConnection([
            Result.ok([
              {..._row(), 'home_goals': 'not-a-number'},
            ]),
          ]),
        );
        final result = await repo.findByFixtureAndParticipant(
          const FixtureRef(_fixtureA),
          const ParticipantId(_participantId),
        );
        expect(result, isA<Err<FixturePredictionView?>>());
        expect(
          (result as Err<FixturePredictionView?>).error.code,
          'prediction.row_corrupt',
        );
      },
    );

    test('a transient connection error passes through verbatim', () async {
      const error = AppError.transient('boom', 'db down');
      final repo = PostgresFixturePredictionRepository(
        _FakeConnection([const Result.err(error)]),
      );
      final result = await repo.findByFixtureAndParticipant(
        const FixtureRef(_fixtureA),
        const ParticipantId(_participantId),
      );
      expect((result as Err<FixturePredictionView?>).error.code, 'boom');
    });
  });
}
