import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// [SuspendedPredictorsReader] over Postgres: the predictions of one fixture
/// joined to their account's status, read fresh on every call (a suspension
/// takes effect on the next scoring, never from a cache).
final class PostgresSuspendedPredictorsReader
    implements SuspendedPredictorsReader {
  /// Creates the reader over [_connection].
  const PostgresSuspendedPredictorsReader(this._connection);

  final PostgresConnection _connection;

  static const String _sql = '''
SELECT fp.participant_id
FROM prediction.fixture_predictions fp
JOIN competition.participants p ON p.id = fp.participant_id
JOIN identity.users u ON u.id = p.user_id
WHERE fp.fixture_id = @fixture_id
  AND (u.status = 'suspended' OR u.hidden_at IS NOT NULL)
''';

  @override
  Future<Result<Set<ParticipantId>>> suspendedOn(FixtureRef fixture) async {
    final result = await _connection.query(
      _sql,
      parameters: {'fixture_id': fixture.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(<ParticipantId>{
        for (final row in value)
          if (row['participant_id'] case final Object id)
            ParticipantId(id.toString()),
      }),
    };
  }
}
