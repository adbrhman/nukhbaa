import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/platform/postgres_app_mode_store.dart';
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

const String _owner = '00000000-0222-4000-8222-000000000001';

// NK292_14
/// Script 292: the adapter the composition root wires for the app's mode.
/// Its table is checked by `supabase/tests/0222_app_mode_test.sql`.
void main() {
  test('reads the mode and its last change', () async {
    final connection = _Connection([
      Result.ok([
        {
          'mode': 'read_only',
          'reason': 'خطأ',
          'changed_by': _owner,
          'changed_at': DateTime.utc(2026, 11, 20, 12),
        },
      ]),
    ]);

    final result = await PostgresAppModeStore(connection).read();

    final AppModeState state = (result as Ok<AppModeState>).value;
    expect(state.mode, AppMode.readOnly);
    expect(state.changedBy, const UserId(_owner));
    expect(connection.sql.single, contains('ops.app_mode'));
  });

  test('no row is normal; an unknown mode is corrupt', () async {
    final connection = _Connection([
      const Result.ok([]),
      const Result.ok([
        {
          'mode': 'off',
          'reason': null,
          'changed_by': null,
          'changed_at': '2026-11-20T00:00:00Z',
        },
      ]),
    ]);
    final store = PostgresAppModeStore(connection);

    expect((await store.read() as Ok<AppModeState>).value.mode, AppMode.normal);
    expect(
      (await store.read() as Err<AppModeState>).error.code,
      'ops.row_corrupt',
    );
  });

  test('writes the mode, its reason and its owner', () async {
    final connection = _Connection([
      const Result.ok([
        {'mode': 'closed'},
      ]),
    ]);

    final result = await PostgresAppModeStore(
      connection,
    ).set(mode: AppMode.closed, reason: 'صيانة', by: const UserId(_owner));

    expect(result, isA<Ok<void>>());
    expect(connection.parameters.single, {
      'mode': 'closed',
      'reason': 'صيانة',
      'by': _owner,
    });
  });
}
