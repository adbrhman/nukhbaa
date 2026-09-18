import 'dart:convert';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [GamificationEventSink] (migration 0053).
///
/// Total (Application ADR §2): never throws, binds every value through a
/// `@named` parameter, and speaks only in domain types.
final class PostgresGamificationEventSink implements GamificationEventSink {
  /// Creates the sink over an open [PostgresConnection].
  const PostgresGamificationEventSink(this._connection);

  final PostgresConnection _connection;

  // ON CONFLICT on the dedupe key is what makes every emitter re-runnable:
  // a replayed job inserts nothing the second time instead of raising 23505.
  static const String _insertSql = '''
INSERT INTO gamification.events (
  id, user_id, event_type, payload, ref_type, ref_id,
  dedupe_key, rule_version, occurred_at
)
VALUES (
  @id, @user_id, @event_type, @payload::jsonb, @ref_type, @ref_id,
  @dedupe_key, @rule_version, @occurred_at
)
ON CONFLICT ON CONSTRAINT events_dedupe_key_uniq DO NOTHING
''';

  @override
  Future<Result<void>> record(GamificationEvent event) async {
    final result = await _connection.query(
      _insertSql,
      parameters: {
        'id': event.id.value,
        'user_id': event.userId.value,
        'event_type': event.type.wireName,
        'payload': jsonEncode(event.payload),
        'ref_type': event.refType,
        'ref_id': event.refId,
        'dedupe_key': event.dedupeKey,
        'rule_version': event.ruleVersion,
        'occurred_at': event.occurredAt.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
    };
  }
}
