import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/scoring/postgres_my_fixture_score_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  String? sql;
  Map<String, Object?>? parameters;

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.sql = sql;
    this.parameters = parameters;
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

const _user = UserId('00000000-0000-4000-8171-000000000001');
const _participant = 'c8171000-0000-4000-8000-0000000000a1';
const _f1 = 'c8171000-0000-4000-8000-0000000000f1';
const _f2 = 'c8171000-0000-4000-8000-0000000000f2';

Future<Result<List<MyFixtureScore>>> _read(List<Map<String, dynamic>> rows) =>
    PostgresMyFixtureScoreReader(
      _FakeConnection(Result.ok(rows)),
    ).listByUser(_user);

void main() {
  group('PostgresMyFixtureScoreReader', () {
    test('binds the user and maps a scored row and a waiting one', () async {
      final connection = _FakeConnection(
        const Result.ok(<Map<String, dynamic>>[
          {
            'participant_id': _participant,
            'fixture_id': _f1,
            'grade': 'exact_scoreline',
            'points': 6,
            'result_home_goals': 1,
            'result_away_goals': 0,
          },
          {
            'participant_id': _participant,
            'fixture_id': _f2,
            'grade': null,
            'points': null,
            'result_home_goals': 2,
            'result_away_goals': 1,
          },
        ]),
      );

      final result = await PostgresMyFixtureScoreReader(
        connection,
      ).listByUser(_user);

      final rows = (result as Ok<List<MyFixtureScore>>).value;
      expect(rows, hasLength(2));
      expect(rows.first.participantId, const ParticipantId(_participant));
      expect(rows.first.fixture, const FixtureRef(_f1));
      expect(rows.first.grade, FixtureScoreGrade.exactScoreline);
      expect(rows.first.points, 6);
      expect(rows.first.result?.homeGoals, 1);
      expect(rows.first.result?.awayGoals, 0);
      expect(rows.last.grade, isNull);
      expect(rows.last.points, isNull);
      expect(rows.last.result?.homeGoals, 2);
      expect(rows.last.result?.awayGoals, 1);
      expect(connection.sql, contains('scoring.my_fixture_scores'));
      expect(connection.parameters, <String, Object?>{'user_id': _user.value});
    });

    test('a score without a recorded result keeps a null result', () async {
      final result = await _read([
        {
          'participant_id': _participant,
          'fixture_id': _f1,
          'grade': 'incorrect',
          'points': 0,
          'result_home_goals': null,
          'result_away_goals': null,
        },
      ]);

      final row = (result as Ok<List<MyFixtureScore>>).value.single;
      expect(row.grade, FixtureScoreGrade.incorrect);
      expect(row.points, 0);
      expect(row.result, isNull);
    });

    test('a broken row is reported, not shown half-read', () async {
      for (final broken in <Map<String, dynamic>>[
        {
          'participant_id': 'not-a-uuid',
          'fixture_id': _f1,
          'grade': null,
          'points': null,
          'result_home_goals': 1,
          'result_away_goals': 0,
        },
        {
          'participant_id': _participant,
          'fixture_id': _f1,
          'grade': 'nearly',
          'points': 1,
          'result_home_goals': 1,
          'result_away_goals': 0,
        },
        {
          'participant_id': _participant,
          'fixture_id': _f1,
          'grade': 'incorrect',
          'points': null,
          'result_home_goals': 1,
          'result_away_goals': 0,
        },
        {
          'participant_id': _participant,
          'fixture_id': _f1,
          'grade': null,
          'points': null,
          'result_home_goals': 1,
          'result_away_goals': null,
        },
      ]) {
        final result = await _read([broken]);
        expect(
          (result as Err<List<MyFixtureScore>>).error.code,
          'scoring.row_corrupt',
          reason: '$broken',
        );
      }
    });

    test('a failed query is returned as it came', () async {
      final result = await PostgresMyFixtureScoreReader(
        _FakeConnection(
          const Result.err(
            AppError.transient('db.query_timeout', 'Database query timed out'),
          ),
        ),
      ).listByUser(_user);

      expect(
        (result as Err<List<MyFixtureScore>>).error.code,
        'db.query_timeout',
      );
    });
  });
}
