import 'package:application/application.dart';
import 'package:infrastructure/src/competition/postgres_same_match_finder.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _fixtureId = '11111111-1111-4111-8111-111111111111';
const _lyonId = '22222222-2222-4222-8222-222222222222';
const _palaceId = '33333333-3333-4333-8333-333333333333';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;
  String? lastSql;
  Map<String, Object?>? lastParameters;

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    lastSql = sql;
    lastParameters = parameters;
    return _response;
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) => action(this);

  @override
  Future<void> close() async {}
}

Future<Result<SameMatch?>> _find(
  _FakeConnection connection, {
  String? homeTeamId = _lyonId,
  String? awayTeamId = _palaceId,
}) => PostgresSameMatchFinder(connection).find(
  homeTeam: ' ليون ',
  awayTeam: 'كريستال بالاس',
  homeTeamId: homeTeamId,
  awayTeamId: awayTeamId,
  from: DateTime.utc(2026, 10, 15, 4, 45),
  to: DateTime.utc(2026, 10, 16, 4, 45),
);

void main() {
  test('the row found is the same match, kickoff in UTC', () async {
    final connection = _FakeConnection(
      Result.ok([
        {
          'fixture_id': _fixtureId,
          'home_team': 'ليون',
          'away_team': 'كريستال بالاس',
          'kickoff_at': DateTime.utc(2026, 10, 15, 16, 45),
        },
      ]),
    );

    final result = await _find(connection);

    final same = (result as Ok<SameMatch?>).value!;
    expect(same.fixtureId, _fixtureId);
    expect(same.homeTeam, 'ليون');
    expect(same.awayTeam, 'كريستال بالاس');
    expect(same.kickoffAt, DateTime.utc(2026, 10, 15, 16, 45));
    expect(same.kickoffAt.isUtc, isTrue);
  });

  test('names are trimmed and every value is bound by name', () async {
    final connection = _FakeConnection(const Result.ok([]));

    await _find(connection);

    expect(connection.lastParameters, {
      'home_name': 'ليون',
      'away_name': 'كريستال بالاس',
      'home_id': _lyonId,
      'away_id': _palaceId,
      'from': '2026-10-15T04:45:00.000Z',
      'to': '2026-10-16T04:45:00.000Z',
    });
    // Hidden and test fixtures are never in the way.
    expect(connection.lastSql, contains('AND NOT s.is_test'));
    expect(connection.lastSql, contains('AND s.hidden_at IS NULL'));
  });

  test('a side typed by hand travels as a null team id', () async {
    final connection = _FakeConnection(const Result.ok([]));

    await _find(connection, homeTeamId: null, awayTeamId: null);

    expect(connection.lastParameters!['home_id'], isNull);
    expect(connection.lastParameters!['away_id'], isNull);
  });

  test('no row is no same match', () async {
    final result = await _find(_FakeConnection(const Result.ok([])));

    expect((result as Ok<SameMatch?>).value, isNull);
  });

  test('a malformed row is transient, never a guess', () async {
    final result = await _find(
      _FakeConnection(
        Result.ok([
          {
            'fixture_id': _fixtureId,
            'home_team': 'ليون',
            'away_team': 'كريستال بالاس',
            'kickoff_at': 'not a timestamp',
          },
        ]),
      ),
    );

    final error = (result as Err<SameMatch?>).error;
    expect(error.kind, ErrorKind.transient);
    expect(error.code, 'competition.row_corrupt');
  });

  test('a database failure passes through', () async {
    const failure = AppError.transient('db.query_timeout', 'timed out');

    final result = await _find(_FakeConnection(const Result.err(failure)));

    expect((result as Err<SameMatch?>).error, failure);
  });
}
