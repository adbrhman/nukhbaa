import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:shared/shared.dart';

/// Postgres-backed [H2hChatRepository] (migration 0216, script 281).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter. Every statement finds the caller's group
/// itself, the newest one he sits in, so no group id ever comes from the
/// request. Who may write is the database's own rule (the guard of 0216);
/// its refusals are turned into Arabic answers here.
final class PostgresH2hChatRepository implements H2hChatRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresH2hChatRepository(this._connection);

  final PostgresConnection _connection;

  // The caller's group: the newest month he holds a seat in.
  static const String _myGroup = '''
SELECT lm.league_id
FROM gamification.h2h_league_members lm
WHERE lm.user_id = @player_id::uuid
ORDER BY lm.month_start DESC
LIMIT 1
''';

  // No row for a player with no seat. Unread counts the messages of others
  // after his marker that are not hidden.
  static const String headSql =
      '''
SELECT g.league_id::text AS league_id,
       EXISTS (SELECT 1 FROM chat.muted_users mu
               WHERE mu.user_id = @player_id::uuid) AS muted,
       EXISTS (SELECT 1 FROM chat.rules_acceptances ra
               WHERE ra.user_id = @player_id::uuid) AS rules_accepted,
       (SELECT count(*)
        FROM chat.h2h_messages m
        WHERE m.league_id = g.league_id
          AND m.hidden_at IS NULL
          AND m.sender_id <> @player_id::uuid
          AND m.id > coalesce(
                (SELECT r.last_read_id FROM chat.h2h_reads r
                 WHERE r.league_id = g.league_id
                   AND r.user_id = @player_id::uuid), 0)
       )::bigint AS unread
FROM ($_myGroup) g
''';

  // Newest first, so LIMIT keeps the newest; the page is reversed after.
  static const String messagesSql = '''
SELECT m.id, m.sender_id::text AS sender_id,
       coalesce(u.display_name, '') AS sender_name,
       m.body, m.created_at
FROM chat.h2h_messages m
JOIN identity.users u ON u.id = m.sender_id
WHERE m.league_id = @league_id::uuid
  AND m.hidden_at IS NULL
  AND (@after::bigint IS NULL OR m.id > @after::bigint)
ORDER BY m.id DESC
LIMIT @limit::int
''';

  // No row when the caller has no seat; the database's guard refuses the
  // rest (muted, rules not accepted).
  static const String sendSql =
      '''
WITH ins AS (
  INSERT INTO chat.h2h_messages (league_id, sender_id, body, created_at)
  SELECT g.league_id, @player_id::uuid, @body::text, @at::timestamptz
  FROM ($_myGroup) g
  RETURNING id, created_at
)
SELECT ins.id, ins.created_at,
       coalesce(u.display_name, '') AS sender_name
FROM ins
JOIN identity.users u ON u.id = @player_id::uuid
''';

  // The marker moves to the group's newest message and never back.
  static const String markReadSql =
      '''
INSERT INTO chat.h2h_reads (league_id, user_id, last_read_id, updated_at)
SELECT g.league_id, @player_id::uuid,
       coalesce((SELECT max(m.id) FROM chat.h2h_messages m
                 WHERE m.league_id = g.league_id), 0),
       @at::timestamptz
FROM ($_myGroup) g
ON CONFLICT (league_id, user_id) DO UPDATE
SET last_read_id = greatest(chat.h2h_reads.last_read_id,
                            EXCLUDED.last_read_id),
    updated_at = EXCLUDED.updated_at
''';

  static const String acceptRulesSql = '''
INSERT INTO chat.rules_acceptances (user_id, version, accepted_at)
VALUES (@player_id::uuid, 1, @at::timestamptz)
ON CONFLICT (user_id) DO NOTHING
''';

  /// The answer for a player with no seat in any group.
  static const AppError noGroup = AppError.invariant(
    'h2h.chat_no_group',
    'لا توجد مجموعة لك هذا الشهر.',
  );

  @override
  Future<Result<H2hChatPage>> page({
    required UserId playerId,
    required int? afterId,
    required int limit,
  }) async {
    final head = await _connection.query(
      headSql,
      parameters: {'player_id': playerId.value},
    );
    if (head is Err<List<Map<String, dynamic>>>) return Result.err(head.error);
    final headRows = (head as Ok<List<Map<String, dynamic>>>).value;
    if (headRows.isEmpty) return const Result.ok(H2hChatPage.noGroup);
    final Map<String, dynamic> first = headRows.first;
    final Object? league = first['league_id'];
    if (league is! String) return Result.err(_corrupt('group'));

    final result = await _connection.query(
      messagesSql,
      parameters: {'league_id': league, 'after': afterId, 'limit': limit},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final List<H2hChatMessage> page = <H2hChatMessage>[];
    for (final Map<String, dynamic> row
        in (result as Ok<List<Map<String, dynamic>>>).value) {
      final message = _message(row);
      if (message is Err<H2hChatMessage>) return Result.err(message.error);
      page.add((message as Ok<H2hChatMessage>).value);
    }
    return Result.ok(
      H2hChatPage(
        hasGroup: true,
        muted: first['muted'] == true,
        rulesAccepted: first['rules_accepted'] == true,
        unread: _int(first['unread']),
        messages: List<H2hChatMessage>.unmodifiable(page.reversed),
      ),
    );
  }

  @override
  Future<Result<H2hChatMessage>> send({
    required UserId playerId,
    required H2hChatBody body,
    required DateTime at,
  }) async {
    final result = await _connection.query(
      sendSql,
      parameters: {
        'player_id': playerId.value,
        'body': body.value,
        'at': at.toUtc(),
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(_reclassifySend(result.error));
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) return const Result.err(noGroup);
    final Map<String, dynamic> row = rows.first;
    final Object? createdAt = row['created_at'];
    if (createdAt is! DateTime) return Result.err(_corrupt('message'));
    return Result.ok(
      H2hChatMessage(
        id: _int(row['id']),
        senderId: playerId,
        senderName: (row['sender_name'] as String?) ?? '',
        body: body.value,
        createdAt: createdAt.toUtc(),
      ),
    );
  }

  @override
  Future<Result<void>> markRead({
    required UserId playerId,
    required DateTime at,
  }) async => _done(
    await _connection.query(
      markReadSql,
      parameters: {'player_id': playerId.value, 'at': at.toUtc()},
    ),
  );

  @override
  Future<Result<void>> acceptRules({
    required UserId playerId,
    required DateTime at,
  }) async => _done(
    await _connection.query(
      acceptRulesSql,
      parameters: {'player_id': playerId.value, 'at': at.toUtc()},
    ),
  );

  static Result<void> _done(Result<List<Map<String, dynamic>>> result) =>
      switch (result) {
        Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
        Ok<List<Map<String, dynamic>>>() => const Result.ok(null),
      };

  /// Migration 0216's guard speaks in constraint names; the player gets an
  /// Arabic line, and everything else passes through.
  static AppError _reclassifySend(AppError error) {
    final cause = error.cause;
    if (cause is! ServerException || cause.code != '23514') return error;
    return switch (cause.constraintName) {
      'h2h_messages_sender_muted' => const AppError.invariant(
        'h2h.chat_muted',
        'مُنعت من الكتابة في الدردشة.',
      ),
      'h2h_messages_rules_not_accepted' => const AppError.invariant(
        'h2h.chat_rules_not_accepted',
        'وافق على قواعد الدردشة أولًا.',
      ),
      'h2h_messages_group_closed' ||
      'h2h_messages_member_only' => const AppError.invariant(
        'h2h.chat_closed',
        'هذه الدردشة مغلقة، انتقلت إلى مجموعة جديدة.',
      ),
      _ => error,
    };
  }

  static Result<H2hChatMessage> _message(Map<String, dynamic> row) {
    final Object? sender = row['sender_id'];
    final Object? body = row['body'];
    final Object? createdAt = row['created_at'];
    if (sender is! String || body is! String || createdAt is! DateTime) {
      return Result.err(_corrupt('message'));
    }
    return Result.ok(
      H2hChatMessage(
        id: _int(row['id']),
        senderId: UserId(sender),
        senderName: (row['sender_name'] as String?) ?? '',
        body: body,
        createdAt: createdAt.toUtc(),
      ),
    );
  }

  static AppError _corrupt(String what) => AppError.transient(
    'h2h.chat_row_corrupt',
    'تعذّرت قراءة الدردشة.',
    'unexpected $what row',
  );

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is BigInt) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
