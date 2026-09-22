import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_prediction_outcome_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    params.add(parameters);
    return _response;
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

/// Hermetic unit tests for the row mapping. Which rows are read is SQL,
/// checked by hand against the live database.
void main() {
  group('outcomesOf', () {
    test('maps a scored row to an outcome', () async {
      final connection = _FakeConnection(
        Result.ok([
          {
            'fixture_id': 'f1',
            'kickoff_at': DateTime.utc(2026, 9, 16, 18),
            'home_team': 'home',
            'away_team': 'away',
            'league_name': null,
            'grade': 'exact_scoreline',
            'points': 3,
            'followed': true,
          },
        ]),
      );

      final result = await PostgresPredictionOutcomeReader(connection)
          .outcomesOf(
            userId: const UserId(_user),
            from: DateTime.utc(2026, 8),
            to: DateTime.utc(2026, 10),
          );

      final outcome = (result as Ok<List<PredictionOutcome>>).value.single;
      expect(outcome.grade, PredictionGrade.exact);
      expect(outcome.followed, isTrue);
      expect(outcome.leagueName, isNull);
      expect(connection.params.single['user_id'], _user);
    });

    test('an unknown grade is transient, not a guess', () async {
      final connection = _FakeConnection(
        Result.ok([
          {
            'fixture_id': 'f1',
            'kickoff_at': DateTime.utc(2026, 9, 16, 18),
            'home_team': 'home',
            'away_team': 'away',
            'league_name': 'L',
            'grade': 'pending',
            'points': 0,
            'followed': false,
          },
        ]),
      );

      final result = await PostgresPredictionOutcomeReader(connection)
          .outcomesOf(
            userId: const UserId(_user),
            from: DateTime.utc(2026, 8),
            to: DateTime.utc(2026, 10),
          );

      expect(
        (result as Err<List<PredictionOutcome>>).error.kind,
        ErrorKind.transient,
      );
    });
  });

  test('communityTally reads the three counts', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'decided': 10, 'correct': 6, 'exact': 2},
      ]),
    );

    final result = await PostgresPredictionOutcomeReader(
      connection,
    ).communityTally(from: DateTime.utc(2026, 9), to: DateTime.utc(2026, 10));

    expect((result as Ok<AccuracyTally>).value.percent, 60);
  });
}
