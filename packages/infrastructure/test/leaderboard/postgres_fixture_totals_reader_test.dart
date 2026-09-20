import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/leaderboard/postgres_fixture_totals_reader.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _fixtureId = 'ffffffff-0000-0000-0000-000000000001';
const _fixtureId2 = 'ffffffff-0000-0000-0000-000000000002';
const _participantId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

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

_FakeConnection _rows(List<Map<String, dynamic>> rows) =>
    _FakeConnection([Result.ok(rows)]);

_FakeConnection _fails() => _FakeConnection([
  const Result.err(
    AppError.transient('db.query_failed', 'Database query failed'),
  ),
]);

void main() {
  test('empty fixture set does not query the database', () async {
    final conn = _rows(const []);
    final reader = PostgresFixtureTotalsReader(conn);

    final result = await reader.totalsFor(const []);

    expect(result, isA<Ok<List<ParticipantFixtureTotals>>>());
    expect((result as Ok<List<ParticipantFixtureTotals>>).value, isEmpty);
    expect(conn.sqls, isEmpty);
  });

  test('reads combined score and streak-bonus totals', () async {
    final conn = _rows([
      {
        'participant_id': _participantId,
        'total_points': BigInt.from(17),
        'fixtures_scored': BigInt.from(2),
        'exact_count': BigInt.from(1),
        'decided_count': BigInt.from(2),
      },
    ]);
    final reader = PostgresFixtureTotalsReader(conn);

    final result = await reader.totalsFor(const [
      FixtureRef(_fixtureId),
      FixtureRef(_fixtureId2),
    ]);

    expect(result, isA<Ok<List<ParticipantFixtureTotals>>>());
    final totals = (result as Ok<List<ParticipantFixtureTotals>>).value;
    expect(totals.single.participantId, const ParticipantId(_participantId));
    expect(totals.single.totalPoints, 17);
    expect(totals.single.fixturesScored, 2);
    expect(totals.single.exactCount, 1);
    expect(totals.single.decidedCount, 2);

    final sql = conn.sqls.single;
    expect(sql, contains('ledger.fixture_point_entries'));
    expect(sql, contains("entry_kind = 'streak_bonus'"));
    expect(sql, contains('LEFT JOIN bonuses'));
    expect(conn.parameters.single, {
      'fixture_ids': [_fixtureId, _fixtureId2],
    });
  });

  test('maps a bonus-only participant with zero score counters', () async {
    final conn = _rows([
      {
        'participant_id': _participantId,
        'total_points': BigInt.from(6),
        'fixtures_scored': BigInt.zero,
        'exact_count': BigInt.zero,
        'decided_count': BigInt.zero,
      },
    ]);
    final result = await PostgresFixtureTotalsReader(
      conn,
    ).totalsFor(const [FixtureRef(_fixtureId)]);
    final totals = (result as Ok<List<ParticipantFixtureTotals>>).value;
    expect(totals.single.totalPoints, 6);
    expect(totals.single.fixturesScored, 0);
    expect(totals.single.exactCount, 0);
    expect(totals.single.decidedCount, 0);
    expect(conn.sqls.single, contains('population AS'));
    expect(conn.sqls.single, contains('SELECT participant_id FROM bonuses'));
  });

  test('preserves score-only and multiple-bonus mapped totals', () async {
    final conn = _rows([
      {
        'participant_id': _participantId,
        'total_points': BigInt.from(11),
        'fixtures_scored': BigInt.one,
        'exact_count': BigInt.one,
        'decided_count': BigInt.one,
      },
      {
        'participant_id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'total_points': BigInt.from(9),
        'fixtures_scored': BigInt.zero,
        'exact_count': BigInt.zero,
        'decided_count': BigInt.zero,
      },
    ]);
    final result = await PostgresFixtureTotalsReader(
      conn,
    ).totalsFor(const [FixtureRef(_fixtureId)]);
    final totals = (result as Ok<List<ParticipantFixtureTotals>>).value;
    expect(totals[0].totalPoints, 11);
    expect(totals[1].totalPoints, 9);
  });

  test('passes a transient query failure through unchanged', () async {
    final reader = PostgresFixtureTotalsReader(_fails());

    final result = await reader.totalsFor(const [FixtureRef(_fixtureId)]);

    expect(result, isA<Err<List<ParticipantFixtureTotals>>>());
    expect(
      (result as Err<List<ParticipantFixtureTotals>>).error.code,
      'db.query_failed',
    );
  });
}
