import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/prediction/postgres_install_fixture_claims.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';
const _fixture = '66666666-6666-4666-8666-666666666666';
const _phone = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

/// Answers each query in turn from [_answers].
final class _ScriptedConnection implements PostgresConnection {
  _ScriptedConnection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sql = <String>[];
  final List<Map<String, Object?>> parameters = <Map<String, Object?>>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String statement, {
    Map<String, Object?> parameters = const {},
  }) async {
    sql.add(statement);
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

Future<Result<UserId>> _claim(_ScriptedConnection connection) =>
    PostgresInstallFixtureClaims(connection).claim(
      installId: _phone,
      fixture: const FixtureRef(_fixture),
      userId: const UserId(_a),
    );

/// Script 200: the store `SubmitFixturePrediction` is wired with. Its SQL
/// runs against the migration in `supabase/tests/0197_shared_devices_test.sql`.
void main() {
  test('answers the account that holds the match', () async {
    final connection = _ScriptedConnection([
      const Result.ok([
        {'user_id': _b},
      ]),
    ]);

    final result = await _claim(connection);

    expect((result as Ok<UserId>).value.value, _b);
    expect(connection.sql, hasLength(1));
    expect(connection.sql.single, contains('prediction.install_claims'));
    expect(connection.sql.single, contains('identity.install_accounts'));
    expect(connection.parameters.single, {
      'install': _phone,
      'fixture_id': _fixture,
      'user_id': _a,
    });
  });

  test('a claim made at the same moment is read once more', () async {
    final connection = _ScriptedConnection([
      const Result.ok([]),
      const Result.ok([
        {'user_id': _b},
      ]),
    ]);

    final result = await _claim(connection);

    expect((result as Ok<UserId>).value.value, _b);
    expect(connection.sql, hasLength(2));
    expect(connection.parameters.last, {
      'install': _phone,
      'fixture_id': _fixture,
    });
  });

  test('neither made nor found is a transient row_corrupt', () async {
    final result = await _claim(
      _ScriptedConnection([const Result.ok([]), const Result.ok([])]),
    );

    expect((result as Err<UserId>).error.code, 'prediction.row_corrupt');
    expect(result.error.kind, ErrorKind.transient);
  });

  test('a database failure is passed on', () async {
    final result = await _claim(
      _ScriptedConnection([
        const Result.err(AppError.transient('db.unavailable', 'down')),
      ]),
    );

    expect((result as Err<UserId>).error.code, 'db.unavailable');
  });
}
