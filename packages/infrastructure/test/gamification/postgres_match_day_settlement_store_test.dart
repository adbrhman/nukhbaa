import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/gamification/postgres_match_day_settlement_store.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Hermetic unit tests for [PostgresMatchDaySettlementStore]: a fake
/// [PostgresConnection] replays scripted rows and records every SQL and
/// parameter set. What only a real server can prove (that the statement
/// inserts the right counts) is checked by hand against the live database.
void main() {
  group('PostgresMatchDaySettlementStore.lastSettledDay', () {
    test('maps the projected text day to a UTC day', () async {
      final connection = _rows([
        {'day': '2026-09-19'},
      ]);

      final result = await PostgresMatchDaySettlementStore(
        connection,
      ).lastSettledDay();

      expect((result as Ok<DateTime?>).value, DateTime.utc(2026, 9, 19));
      expect(connection.sqls.single, contains('gamification.settled_days'));
    });

    test('reads null when nothing is settled yet', () async {
      final nullDay = await PostgresMatchDaySettlementStore(
        _rows([
          {'day': null},
        ]),
      ).lastSettledDay();
      expect((nullDay as Ok<DateTime?>).value, isNull);

      final noRows = await PostgresMatchDaySettlementStore(
        _rows(const <Map<String, dynamic>>[]),
      ).lastSettledDay();
      expect((noRows as Ok<DateTime?>).value, isNull);
    });

    test('maps an unreadable day to a transient error', () async {
      final result = await PostgresMatchDaySettlementStore(
        _rows([
          {'day': 'not-a-date'},
        ]),
      ).lastSettledDay();

      expect((result as Err<DateTime?>).error.code, 'gamification.row_corrupt');
    });

    test('passes a query failure through', () async {
      final result = await PostgresMatchDaySettlementStore(
        _fails(),
      ).lastSettledDay();

      expect((result as Err<DateTime?>).error.code, 'db.query_failed');
    });
  });

  group('PostgresMatchDaySettlementStore.firstFixtureDay', () {
    test('reads the earliest fixture day in Riyadh time', () async {
      final connection = _rows([
        {'day': '2026-08-29'},
      ]);

      final result = await PostgresMatchDaySettlementStore(
        connection,
      ).firstFixtureDay();

      expect((result as Ok<DateTime?>).value, DateTime.utc(2026, 8, 29));
      expect(connection.sqls.single, contains("'Asia/Riyadh'"));
    });
  });

  group('PostgresMatchDaySettlementStore.settle', () {
    test('binds the span as ISO days and counts the inserted rows', () async {
      final connection = _rows([
        {'day': '2026-09-18'},
        {'day': '2026-09-19'},
      ]);

      final result = await PostgresMatchDaySettlementStore(connection).settle(
        from: DateTime.utc(2026, 9, 18),
        through: DateTime.utc(2026, 9, 19),
      );

      expect((result as Ok<int>).value, 2);
      expect(connection.parameters.single, {
        'from': '2026-09-18',
        'through': '2026-09-19',
      });
    });

    test('is idempotent in SQL: a settled day is never overwritten', () async {
      final connection = _rows(const <Map<String, dynamic>>[]);

      final result = await PostgresMatchDaySettlementStore(connection).settle(
        from: DateTime.utc(2026, 9, 18),
        through: DateTime.utc(2026, 9, 19),
      );

      expect((result as Ok<int>).value, 0);
      expect(connection.sqls.single, contains('ON CONFLICT (day) DO NOTHING'));
      expect(connection.sqls.single, contains('RETURNING day'));
    });

    test('passes a query failure through', () async {
      final result = await PostgresMatchDaySettlementStore(_fails()).settle(
        from: DateTime.utc(2026, 9, 18),
        through: DateTime.utc(2026, 9, 19),
      );

      expect((result as Err<int>).error.code, 'db.query_failed');
    });
  });
}

/// A [PostgresConnection] test double that replays a scripted queue of
/// [Result]s (one per `query`) and records every SQL and parameter set.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._responses);

  final List<Result<List<Map<String, dynamic>>>> _responses;
  int _index = 0;

  final List<String> sqls = <String>[];
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

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
  ) async {
    return action(this);
  }

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
