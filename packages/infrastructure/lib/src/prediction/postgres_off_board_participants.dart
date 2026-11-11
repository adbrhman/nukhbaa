import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/common/ttl_cache.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// [OffBoardParticipants] over Postgres (script 261): every participant
/// whose account is suspended or hidden, in one small query, held for
/// [ttl] so a board read costs no query at all most of the time. A
/// suspension or a hiding reaches the boards within [ttl]; a failed read is
/// never held.
final class PostgresOffBoardParticipants implements OffBoardParticipants {
  /// Creates the reader over [_connection]; [now] is injectable for tests.
  PostgresOffBoardParticipants(
    this._connection, {
    this.ttl = const Duration(minutes: 1),
    DateTime Function() now = DateTime.now,
  }) : _held = TtlCache<int, Set<ParticipantId>>(
         ttl: ttl,
         maxEntries: 1,
         now: now,
       );

  final PostgresConnection _connection;

  /// How long one answer is held.
  final Duration ttl;

  final TtlCache<int, Set<ParticipantId>> _held;

  static const String _sql = '''
SELECT p.id AS participant_id
FROM competition.participants p
JOIN identity.users u ON u.id = p.user_id
WHERE u.status = 'suspended' OR u.hidden_at IS NOT NULL
''';

  @override
  Future<Result<Set<ParticipantId>>> all() async {
    final held = _held.read(0);
    if (held != null) {
      return Result.ok(held);
    }
    final startedAt = _held.generation;
    final result = await _connection.query(_sql);
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final found = Set<ParticipantId>.unmodifiable(<ParticipantId>{
      for (final row in (result as Ok<List<Map<String, dynamic>>>).value)
        if (row['participant_id'] case final Object id)
          ParticipantId(id.toString()),
    });
    _held.write(0, found, startedAt: startedAt);
    return Result.ok(found);
  }
}
