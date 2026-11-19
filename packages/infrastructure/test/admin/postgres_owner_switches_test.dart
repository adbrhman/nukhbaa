import 'package:application/application.dart';
import 'package:infrastructure/src/admin/postgres_owner_switches.dart';
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

/// Script 286: the adapter the composition root wires for the owners'
/// switches. Its table is checked by
/// `supabase/tests/0218_owner_switches_test.sql`.
void main() {
  test('reads the crowning switch by its key, every call', () async {
    final connection = _Connection([
      const Result.ok([
        {'is_on': false},
      ]),
      const Result.ok([
        {'is_on': true},
      ]),
    ]);
    final switches = PostgresOwnerSwitches(connection);

    expect(
      (await switches.isOn(OwnerSwitch.crowning) as Ok<bool>).value,
      isFalse,
    );
    expect(
      (await switches.isOn(OwnerSwitch.crowning) as Ok<bool>).value,
      isTrue,
    );
    expect(connection.sql, hasLength(2), reason: 'nothing is cached');
    expect(connection.sql.first, contains('ops.owner_switches'));
    expect(connection.parameters.first['key'], 'crowning');
  });

  test('a switch without its row is on', () async {
    final connection = _Connection([const Result.ok([])]);

    final result = await PostgresOwnerSwitches(
      connection,
    ).isOn(OwnerSwitch.crowning);

    expect((result as Ok<bool>).value, isTrue);
  });

  test('a row that is not a flag is corrupt', () async {
    final connection = _Connection([
      const Result.ok([
        {'is_on': 'no'},
      ]),
    ]);

    final result = await PostgresOwnerSwitches(
      connection,
    ).isOn(OwnerSwitch.crowning);

    expect((result as Err<bool>).error.code, 'ops.row_corrupt');
  });

  test('a failed read is passed on', () async {
    final connection = _Connection([
      const Result.err(AppError.transient('db.down', 'down')),
    ]);

    final result = await PostgresOwnerSwitches(
      connection,
    ).isOn(OwnerSwitch.crowning);

    expect((result as Err<bool>).error.code, 'db.down');
  });
}
