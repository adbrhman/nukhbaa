import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/prediction/postgres_fixture_prediction_tally_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _fixtureA = '11111111-1111-1111-1111-111111111111';
const _fixtureB = '22222222-2222-2222-2222-222222222222';

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

List<FixtureOutcomeTally> _ok(Result<List<FixtureOutcomeTally>> result) =>
    (result as Ok<List<FixtureOutcomeTally>>).value;

void main() {
  group('PostgresFixturePredictionTallyReader', () {
    test('an empty fixture set never touches storage', () async {
      final connection = _FakeConnection(const []);
      final reader = PostgresFixturePredictionTallyReader(connection);

      final result = await reader.tallyByFixtures(const []);

      expect(_ok(result), isEmpty);
      expect(connection.parameters, isEmpty);
    });

    test(
      'every fixture is tallied in ONE query, bound as an id array',
      () async {
        final connection = _FakeConnection([
          Result.ok([
            {'fixture_id': _fixtureA, 'home_wins': 3, 'away_wins': 1},
            {'fixture_id': _fixtureB, 'home_wins': 0, 'away_wins': 2},
          ]),
        ]);
        final reader = PostgresFixturePredictionTallyReader(connection);

        final result = await reader.tallyByFixtures(const [
          FixtureRef(_fixtureA),
          FixtureRef(_fixtureB),
        ]);

        expect(
          connection.parameters,
          hasLength(1),
          reason: 'one query for the whole set, never one per fixture',
        );
        expect(connection.parameters.single['fixture_ids'], <String>[
          _fixtureA,
          _fixtureB,
        ]);

        final tallies = _ok(result);
        expect(tallies, hasLength(2));
        expect(tallies.first.fixture.value, _fixtureA);
        expect(tallies.first.homeWinPercentage, 75);
        expect(tallies.first.awayWinPercentage, 25);
        expect(tallies.last.homeWinPercentage, 0);
        expect(tallies.last.awayWinPercentage, 100);
      },
    );

    test('a count that arrives as text is still a count', () async {
      final connection = _FakeConnection([
        Result.ok([
          {'fixture_id': _fixtureA, 'home_wins': '1', 'away_wins': '3'},
        ]),
      ]);
      final reader = PostgresFixturePredictionTallyReader(connection);

      final tallies = _ok(
        await reader.tallyByFixtures(const [FixtureRef(_fixtureA)]),
      );

      expect(tallies.single.homeWins, 1);
      expect(tallies.single.homeWinPercentage, 25);
    });

    test('a fixture nobody predicted is absent, not a zero row', () async {
      final connection = _FakeConnection([
        Result.ok([
          {'fixture_id': _fixtureA, 'home_wins': 1, 'away_wins': 0},
        ]),
      ]);
      final reader = PostgresFixturePredictionTallyReader(connection);

      final tallies = _ok(
        await reader.tallyByFixtures(const [
          FixtureRef(_fixtureA),
          FixtureRef(_fixtureB),
        ]),
      );

      expect(tallies, hasLength(1));
      expect(tallies.single.fixture.value, _fixtureA);
    });

    test('a driver failure propagates untouched', () async {
      final connection = _FakeConnection([
        const Result.err(
          AppError.transient('db.query_failed', 'Connection reset'),
        ),
      ]);
      final reader = PostgresFixturePredictionTallyReader(connection);

      final result = await reader.tallyByFixtures(const [
        FixtureRef(_fixtureA),
      ]);

      expect(result, isA<Err<List<FixtureOutcomeTally>>>());
      expect(
        (result as Err<List<FixtureOutcomeTally>>).error.code,
        'db.query_failed',
      );
    });
  });

  group('FixtureOutcomeTally', () {
    test('draws count on neither side and leave the denominator', () {
      const tally = FixtureOutcomeTally(
        fixture: FixtureRef(_fixtureA),
        homeWins: 1,
        awayWins: 1,
      );

      expect(tally.homeWinPercentage, 50);
      expect(tally.awayWinPercentage, 50);
    });

    test('no decisive prediction is 0/0, never a division by zero', () {
      const tally = FixtureOutcomeTally(
        fixture: FixtureRef(_fixtureA),
        homeWins: 0,
        awayWins: 0,
      );

      expect(tally.homeWinPercentage, 0);
      expect(tally.awayWinPercentage, 0);
    });
  });
}
