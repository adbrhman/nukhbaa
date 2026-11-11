import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/prediction/postgres_off_board_participants.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _a = '11111111-1111-4111-8111-111111111111';
const _b = '22222222-2222-4222-8222-222222222222';

/// Answers each query in turn from [_answers].
final class _Connection implements PostgresConnection {
  _Connection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sql = <String>[];

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    this.sql.add(sql);
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

/// Script 261: the adapter the composition root wires for the boards of a
/// match. Its SQL runs against the schema in
/// `supabase/tests/0208_support_predictions_viewed_audit_test.sql`.
void main() {
  test('reads the suspended and hidden participants once a minute', () async {
    var now = DateTime.utc(2026, 11, 12, 15);
    final connection = _Connection([
      Result.ok([
        {'participant_id': _a},
        {'participant_id': _b},
      ]),
      Result.ok([
        {'participant_id': _b},
      ]),
    ]);
    final reader = PostgresOffBoardParticipants(connection, now: () => now);

    final first = await reader.all();
    now = now.add(const Duration(seconds: 59));
    final held = await reader.all();
    now = now.add(const Duration(seconds: 1));
    final fresh = await reader.all();

    expect((first as Ok<Set<ParticipantId>>).value, {
      const ParticipantId(_a),
      const ParticipantId(_b),
    });
    expect((held as Ok<Set<ParticipantId>>).value, first.value);
    expect((fresh as Ok<Set<ParticipantId>>).value, {const ParticipantId(_b)});
    expect(connection.sql, hasLength(2));
    expect(connection.sql.first, contains("u.status = 'suspended'"));
    expect(connection.sql.first, contains('u.hidden_at IS NOT NULL'));
  });

  test('a failed read is the error itself, and is not held', () async {
    final connection = _Connection([
      const Result.err(AppError.transient('db.down', 'down')),
      const Result.ok(<Map<String, dynamic>>[]),
    ]);
    final reader = PostgresOffBoardParticipants(connection);

    final failed = await reader.all();
    final next = await reader.all();

    expect((failed as Err<Set<ParticipantId>>).error.code, 'db.down');
    expect((next as Ok<Set<ParticipantId>>).value, isEmpty);
    expect(connection.sql, hasLength(2));
  });
}
