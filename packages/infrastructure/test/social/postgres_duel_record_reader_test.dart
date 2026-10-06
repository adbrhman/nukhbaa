import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/social/postgres_duel_record_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._response);

  final Result<List<Map<String, dynamic>>> _response;

  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
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

const _season = '11111111-1111-4111-8111-111111111111';
const _p1 = '44444444-4444-4444-8444-444444444444';
const _p2 = '55555555-5555-4555-8555-555555555555';

SeasonId _seasonId() => (SeasonId.tryParse(_season) as Ok<SeasonId>).value;
ParticipantId _id(String raw) =>
    (ParticipantId.tryParse(raw) as Ok<ParticipantId>).value;

/// Hermetic tests of the binding and the mapping. The statement runs
/// against the real tables in supabase/tests/duel_wins_query_test.sql.
void main() {
  test('binds the season and maps each player wins', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'participant_id': _p1, 'wins': 3},
        {'participant_id': _p2, 'wins': 1},
      ]),
    );

    final result = await PostgresDuelRecordReader(
      connection,
    ).winsInSeason(_seasonId());

    expect((result as Ok<Map<ParticipantId, int>>).value, {
      _id(_p1): 3,
      _id(_p2): 1,
    });
    expect(connection.sqls.single, PostgresDuelRecordReader.winsSql);
    expect(connection.params.single, {'season_id': _season});
  });

  test('no settled duel is an empty map', () async {
    final connection = _FakeConnection(const Result.ok([]));

    final result = await PostgresDuelRecordReader(
      connection,
    ).winsInSeason(_seasonId());

    expect((result as Ok<Map<ParticipantId, int>>).value, isEmpty);
  });

  test('a count that is not a positive integer is corrupt', () async {
    final connection = _FakeConnection(
      const Result.ok([
        {'participant_id': _p1, 'wins': 0},
      ]),
    );

    final result = await PostgresDuelRecordReader(
      connection,
    ).winsInSeason(_seasonId());

    expect(
      (result as Err<Map<ParticipantId, int>>).error.code,
      'social.duel_wins_row_corrupt',
    );
  });

  test('a driver failure is returned, not thrown', () async {
    final connection = _FakeConnection(
      const Result.err(AppError.transient('db.unavailable', 'down')),
    );

    final result = await PostgresDuelRecordReader(
      connection,
    ).winsInSeason(_seasonId());

    expect(
      (result as Err<Map<ParticipantId, int>>).error.code,
      'db.unavailable',
    );
  });
}
