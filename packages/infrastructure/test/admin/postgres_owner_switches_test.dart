import 'package:application/application.dart';
import 'package:domain/domain.dart';
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

  // NK289_08
  group('the owners\' hands on them (script 289)', () {
    const String owner = '11111111-2222-4333-8444-555555555555';

    test('reads every known switch and its last change', () async {
      final connection = _Connection([
        Result.ok([
          {
            'switch_key': 'crowning',
            'is_on': false,
            'reason': 'مراجعة',
            'changed_by': owner,
            'changed_at': DateTime.utc(2026, 11, 30, 18),
          },
          {
            'switch_key': 'later',
            'is_on': true,
            'reason': null,
            'changed_by': null,
            'changed_at': DateTime.utc(2026, 11, 20),
          },
        ]),
      ]);

      final result = await PostgresOwnerSwitches(connection).all();

      final OwnerSwitchState state =
          (result as Ok<List<OwnerSwitchState>>).value.single;
      expect(state.which, OwnerSwitch.crowning);
      expect(state.isOn, isFalse);
      expect(state.reason, 'مراجعة');
      expect(state.changedBy, const UserId(owner));
      expect(state.changedAt, DateTime.utc(2026, 11, 30, 18));
      expect(connection.sql.single, contains('ops.owner_switches'));
    });

    test('a switch never changed has no author', () async {
      final connection = _Connection([
        const Result.ok([
          {
            'switch_key': 'crowning',
            'is_on': true,
            'reason': null,
            'changed_by': null,
            'changed_at': '2026-11-20T00:00:00Z',
          },
        ]),
      ]);

      final result = await PostgresOwnerSwitches(connection).all();

      final OwnerSwitchState state =
          (result as Ok<List<OwnerSwitchState>>).value.single;
      expect(state.isOn, isTrue);
      expect(state.changedBy, isNull);
      expect(state.reason, isNull);
    });

    test('a row that is not a flag is corrupt', () async {
      final connection = _Connection([
        const Result.ok([
          {
            'switch_key': 'crowning',
            'is_on': 'no',
            'reason': null,
            'changed_by': null,
            'changed_at': '2026-11-20T00:00:00Z',
          },
        ]),
      ]);

      final result = await PostgresOwnerSwitches(connection).all();

      expect(
        (result as Err<List<OwnerSwitchState>>).error.code,
        'ops.row_corrupt',
      );
    });

    test('writes the switch, its reason and its owner', () async {
      final connection = _Connection([
        const Result.ok([
          {'switch_key': 'crowning'},
        ]),
      ]);

      final result = await PostgresOwnerSwitches(connection).set(
        which: OwnerSwitch.crowning,
        on: false,
        reason: 'مراجعة',
        by: const UserId(owner),
      );

      expect(result, isA<Ok<void>>());
      expect(connection.sql.single, contains('ON CONFLICT (switch_key)'));
      expect(connection.parameters.single, {
        'key': 'crowning',
        'on': false,
        'reason': 'مراجعة',
        'by': owner,
      });
    });

    test('a write that returns no row is corrupt', () async {
      final connection = _Connection([const Result.ok([])]);

      final result = await PostgresOwnerSwitches(connection).set(
        which: OwnerSwitch.crowning,
        on: true,
        reason: 'x',
        by: const UserId(owner),
      );

      expect((result as Err<void>).error.code, 'ops.row_corrupt');
    });
  });
}
