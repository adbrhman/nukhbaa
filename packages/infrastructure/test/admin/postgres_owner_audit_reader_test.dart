import 'package:application/application.dart';
import 'package:infrastructure/src/admin/postgres_owner_audit_reader.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Answers each query in turn from [_answers].
final class _Connection implements PostgresConnection {
  _Connection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sql = <String>[];
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.sql.add(sql);
    this.parameters.add(parameters);
    return _answers.removeAt(0);
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

/// One row as the query returns it; any column can be spoiled.
Map<String, dynamic> _row({
  Object? source = 'owner',
  Object? id = 1,
  Object? actorName = 'Owner',
  Object? method = 'POST',
  Object? path = '/owner/switches',
  Object? occurredAt,
  Object? target,
  Object? result,
}) => <String, dynamic>{
  'source': source,
  'id': id,
  'actor_name': actorName,
  'method': method,
  'path': path,
  'occurred_at': occurredAt ?? DateTime.utc(2026, 11, 26, 12),
  'target': target,
  'result': result,
};

Future<Result<List<OwnerAuditLine>>> _read(List<Map<String, dynamic>> rows) {
  final connection = _Connection([Result.ok(rows)]);
  return PostgresOwnerAuditReader(connection).latest();
}

// NK342_02
/// Script 342: the adapter the composition root wires (343) for the owners'
/// own audit log. The query itself runs on a real Postgres only; these tests
/// cover the row mapping, the parameters and the shape of the statement.
void main() {
  test('reads both sources as one list, keeping the query order', () async {
    final connection = _Connection([
      Result.ok([
        _row(
          source: 'admin',
          id: 9,
          actorName: 'Owner',
          method: 'PUT',
          path: '/fixtures/abc/result',
          occurredAt: DateTime.utc(2026, 11, 26, 12, 5),
          target: 'A \u00d7 B',
          result: '2-1',
        ),
        _row(id: 9, occurredAt: DateTime.utc(2026, 11, 26, 12)),
        _row(id: 3, occurredAt: DateTime.utc(2026, 11, 26, 11)),
      ]),
    ]);

    final result = await PostgresOwnerAuditReader(connection).latest(limit: 5);

    final List<OwnerAuditLine> lines =
        (result as Ok<List<OwnerAuditLine>>).value;
    expect(lines.map((l) => l.source), ['admin', 'owner', 'owner']);
    expect(lines.map((l) => l.id), [9, 9, 3]);
    expect(lines.first.actorName, 'Owner');
    expect(lines.first.method, 'PUT');
    expect(lines.first.path, '/fixtures/abc/result');
    expect(lines.first.target, 'A \u00d7 B');
    expect(lines.first.result, '2-1');
    expect(lines.first.at, DateTime.utc(2026, 11, 26, 12, 5));
    expect(lines[1].target, isNull);
    expect(lines[1].result, isNull);
    expect(connection.parameters.single, {'limit': 5});
  });

  test('asks for 200 lines when no limit is given', () async {
    final connection = _Connection([const Result.ok([])]);

    final result = await PostgresOwnerAuditReader(connection).latest();

    expect((result as Ok<List<OwnerAuditLine>>).value, isEmpty);
    expect(connection.parameters.single, {'limit': 200});
  });

  test('a time that arrives as text is read as UTC', () async {
    final result = await _read([_row(occurredAt: '2026-11-26T12:00:00Z')]);

    final OwnerAuditLine line =
        (result as Ok<List<OwnerAuditLine>>).value.single;
    expect(line.at, DateTime.utc(2026, 11, 26, 12));
    expect(line.at.isUtc, isTrue);
  });

  test('the statement reads both tables and isolates by the seat table', () {
    final String sql = PostgresOwnerAuditReader.latestSql;

    expect(sql, contains('FROM admin.owner_audit_log l'));
    expect(sql, contains('FROM admin.admin_activity_log l'));
    expect(
      sql,
      contains('JOIN admin.platform_owners o ON o.user_id = l.actor_id'),
    );
    expect(sql, isNot(contains('active_owners')));
    expect(sql, contains('ORDER BY occurred_at DESC, source, id DESC'));
    expect(sql, contains('LIMIT @limit'));
  });

  group('a malformed row is a transient admin.row_corrupt', () {
    final cases = <String, Map<String, dynamic>>{
      'a text id': _row(id: 'x'),
      'an unknown source': _row(source: 'player'),
      'no source': _row(source: null),
      'no path': _row(path: null),
      'no actor name': _row(actorName: null),
      'an unreadable time': _row(occurredAt: 'not a time'),
    };
    cases.forEach((name, row) {
      test(name, () async {
        final result = await _read([row]);

        final AppError error = (result as Err<List<OwnerAuditLine>>).error;
        expect(error.kind, ErrorKind.transient);
        expect(error.code, 'admin.row_corrupt');
      });
    });
  });

  test('one bad row among good ones fails the whole read', () async {
    final result = await _read([_row(), _row(id: 'x')]);

    expect(result, isA<Err<List<OwnerAuditLine>>>());
  });

  test('a database failure passes through unchanged', () async {
    final connection = _Connection([
      const Result.err(AppError.transient('db.down', 'down')),
    ]);

    final result = await PostgresOwnerAuditReader(connection).latest();

    final AppError error = (result as Err<List<OwnerAuditLine>>).error;
    expect(error.kind, ErrorKind.transient);
    expect(error.code, 'db.down');
  });
}
