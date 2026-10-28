import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:shared/shared.dart';

/// Postgres-backed [SupportChatRepository] (migration 0187).
///
/// Total (Application ADR section 2): never throws, binds every value
/// through a `@named` parameter. A message and its conversation's counters
/// change in one statement, under a lock on the conversation row, so two
/// messages at once never lose a count.
final class PostgresSupportChatRepository implements SupportChatRepository {
  /// Creates the repository over an open [PostgresConnection].
  const PostgresSupportChatRepository(this._connection);

  final PostgresConnection _connection;

  // The player's one conversation, created by his first message.
  static const String ensureSql = '''
INSERT INTO support.conversations (player_id, created_at, updated_at)
VALUES (@player_id::uuid, @at::timestamptz, @at::timestamptz)
ON CONFLICT (player_id) DO NOTHING
''';

  // The message, the support side's unread count and the last-message line
  // in one statement; unread_before is the count before this message. A
  // player who writes reopens a closed or archived conversation.
  static const String playerMessageSql = '''
WITH conv AS (
  SELECT c.id, c.support_unread
  FROM support.conversations c
  WHERE c.player_id = @player_id::uuid
  FOR UPDATE
), msg AS (
  INSERT INTO support.messages (
    conversation_id, sender_id, sender_role, body, created_at
  )
  SELECT conv.id, @player_id::uuid, 'player', @body::text, @at::timestamptz
  FROM conv
  RETURNING id, conversation_id, created_at
), touched AS (
  UPDATE support.conversations c
  SET support_unread = c.support_unread + 1,
      status = 'open',
      last_message_at = msg.created_at,
      last_message_preview = @preview::text,
      last_sender_role = 'player',
      updated_at = msg.created_at
  FROM msg
  WHERE c.id = msg.conversation_id
  RETURNING c.id
)
SELECT msg.id,
       msg.conversation_id::text AS conversation_id,
       msg.created_at,
       conv.support_unread::bigint AS unread_before,
       coalesce(u.display_name, '') AS player_name
FROM msg
JOIN conv ON conv.id = msg.conversation_id
JOIN identity.users u ON u.id = @player_id::uuid
''';

  // Support's answer: the player's unread count and the last-message line.
  // No row when the conversation is not on file.
  static const String supportReplySql = '''
WITH conv AS (
  SELECT c.id, c.player_id, c.player_unread
  FROM support.conversations c
  WHERE c.id = @conversation_id::uuid
  FOR UPDATE
), msg AS (
  INSERT INTO support.messages (
    conversation_id, sender_id, sender_role, body, created_at
  )
  SELECT conv.id, @admin_id::uuid, 'support', @body::text, @at::timestamptz
  FROM conv
  RETURNING id, conversation_id, created_at
), touched AS (
  UPDATE support.conversations c
  SET player_unread = c.player_unread + 1,
      last_message_at = msg.created_at,
      last_message_preview = @preview::text,
      last_sender_role = 'support',
      updated_at = msg.created_at
  FROM msg
  WHERE c.id = msg.conversation_id
  RETURNING c.id
)
SELECT msg.id,
       msg.conversation_id::text AS conversation_id,
       msg.created_at,
       conv.player_unread::bigint AS unread_before,
       coalesce(u.display_name, '') AS player_name
FROM msg
JOIN conv ON conv.id = msg.conversation_id
JOIN identity.users u ON u.id = conv.player_id
''';

  static const String playerHeadSql = '''
SELECT c.id::text AS id, c.status, c.player_unread::bigint AS unread
FROM support.conversations c
WHERE c.player_id = @player_id::uuid
''';

  // One more than the page, newest first: the extra row says older ones
  // are left.
  static const String messagesSql = '''
SELECT m.id, m.sender_role, m.body, m.created_at, m.read_at
FROM support.messages m
WHERE m.conversation_id = @conversation_id::uuid
  AND (@before::bigint IS NULL OR m.id < @before::bigint)
ORDER BY m.id DESC
LIMIT @limit::int
''';

  static const String _summaryColumns = '''
SELECT c.id::text AS id,
       c.player_id::text AS player_id,
       coalesce(u.display_name, '') AS player_name,
       c.status,
       coalesce(c.last_message_at, c.created_at) AS last_message_at,
       coalesce(c.last_message_preview, '') AS last_message_preview,
       coalesce(c.last_sender_role, 'player') AS last_sender_role,
       c.support_unread::bigint AS support_unread,
       c.player_unread::bigint AS player_unread
FROM support.conversations c
JOIN identity.users u ON u.id = c.player_id
''';

  static const String conversationSql =
      '''
$_summaryColumns
WHERE c.id = @conversation_id::uuid
''';

  static const String inboxSql =
      '''
$_summaryColumns
WHERE c.last_message_at IS NOT NULL
  AND CASE @filter::text
        WHEN 'unread' THEN c.support_unread > 0
        WHEN 'open' THEN c.status = 'open'
        WHEN 'closed' THEN c.status IN ('closed', 'archived')
        ELSE true
      END
  AND (@search::text = ''
       OR strpos(lower(coalesce(u.display_name, '')),
                 lower(@search::text)) > 0)
ORDER BY c.last_message_at DESC, c.id
LIMIT @limit::int
''';

  static const String unreadConversationsSql = '''
SELECT count(*)::bigint AS unread
FROM support.conversations c
WHERE c.support_unread > 0
''';

  static const String markReadByPlayerSql = '''
WITH conv AS (
  SELECT c.id
  FROM support.conversations c
  WHERE c.player_id = @player_id::uuid
  FOR UPDATE
), marked AS (
  UPDATE support.messages m
  SET read_at = @at::timestamptz
  FROM conv
  WHERE m.conversation_id = conv.id
    AND m.sender_role = 'support'
    AND m.read_at IS NULL
  RETURNING m.id
), reset AS (
  UPDATE support.conversations c
  SET player_unread = 0
  FROM conv
  WHERE c.id = conv.id AND c.player_unread <> 0
  RETURNING c.id
)
SELECT (SELECT count(*) FROM marked)::bigint AS marked,
       (SELECT count(*) FROM conv)::bigint AS found
''';

  static const String markReadBySupportSql = '''
WITH conv AS (
  SELECT c.id
  FROM support.conversations c
  WHERE c.id = @conversation_id::uuid
  FOR UPDATE
), marked AS (
  UPDATE support.messages m
  SET read_at = @at::timestamptz
  FROM conv
  WHERE m.conversation_id = conv.id
    AND m.sender_role = 'player'
    AND m.read_at IS NULL
  RETURNING m.id
), reset AS (
  UPDATE support.conversations c
  SET support_unread = 0
  FROM conv
  WHERE c.id = conv.id AND c.support_unread <> 0
  RETURNING c.id
)
SELECT (SELECT count(*) FROM marked)::bigint AS marked,
       (SELECT count(*) FROM conv)::bigint AS found
''';

  static const String playerUnreadSql = '''
SELECT coalesce((
  SELECT c.player_unread
  FROM support.conversations c
  WHERE c.player_id = @player_id::uuid
), 0)::bigint AS unread
''';

  static const String setStatusSql = '''
UPDATE support.conversations c
SET status = @status::text, updated_at = @at::timestamptz
WHERE c.id = @conversation_id::uuid
RETURNING c.id::text AS id
''';

  // Only an active account's phones: a suspended or deleted player is not
  // rung.
  static const String playerTokensSql = '''
SELECT dt.token
FROM support.conversations c
JOIN identity.users u ON u.id = c.player_id
JOIN notification.device_tokens dt ON dt.user_id = u.id
WHERE c.id = @conversation_id::uuid
  AND u.status = 'active'
ORDER BY dt.token
''';

  @override
  Future<Result<SupportMessageStored>> addPlayerMessage({
    required UserId playerId,
    required SupportMessageBody body,
    required DateTime at,
  }) => _connection.runInTransaction<SupportMessageStored>((tx) async {
    final ensured = await tx.query(
      ensureSql,
      parameters: {'player_id': playerId.value, 'at': at.toUtc()},
    );
    if (ensured is Err<List<Map<String, dynamic>>>) {
      return Result.err(ensured.error);
    }
    final stored = await tx.query(
      playerMessageSql,
      parameters: {
        'player_id': playerId.value,
        'body': body.value,
        'preview': body.preview,
        'at': at.toUtc(),
      },
    );
    return _stored(stored, body.value, SupportSenderRole.player);
  });

  @override
  Future<Result<SupportMessageStored>> addSupportReply({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportMessageBody body,
    required DateTime at,
  }) async {
    final stored = await _connection.query(
      supportReplySql,
      parameters: {
        'conversation_id': conversationId.value,
        'admin_id': adminId.value,
        'body': body.value,
        'preview': body.preview,
        'at': at.toUtc(),
      },
    );
    return _stored(stored, body.value, SupportSenderRole.support);
  }

  @override
  Future<Result<SupportThread>> playerThread({
    required UserId playerId,
    required int? beforeId,
    required int limit,
  }) async {
    final head = await _connection.query(
      playerHeadSql,
      parameters: {'player_id': playerId.value},
    );
    if (head is Err<List<Map<String, dynamic>>>) return Result.err(head.error);
    final rows = (head as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) {
      return const Result.ok(
        SupportThread(
          status: null,
          unread: 0,
          messages: <SupportMessage>[],
          hasMore: false,
        ),
      );
    }
    final status = SupportConversationStatus.tryParse(
      rows.first['status'] as String?,
    );
    if (status is Err<SupportConversationStatus>) {
      return Result.err(_corrupt('status', status.error.message));
    }
    return _thread(
      conversationId: rows.first['id'] as String,
      status: (status as Ok<SupportConversationStatus>).value,
      unread: _int(rows.first['unread']),
      beforeId: beforeId,
      limit: limit,
    );
  }

  @override
  Future<Result<SupportThread>> conversationThread({
    required SupportConversationId conversationId,
    required int? beforeId,
    required int limit,
  }) async {
    final summary = await conversation(conversationId);
    return switch (summary) {
      Err<SupportConversationSummary>(:final error) => Result.err(error),
      Ok<SupportConversationSummary>(:final value) => _thread(
        conversationId: value.id.value,
        status: value.status,
        unread: value.supportUnread,
        beforeId: beforeId,
        limit: limit,
      ),
    };
  }

  @override
  Future<Result<int>> markReadByPlayer({
    required UserId playerId,
    required DateTime at,
  }) async {
    final result = await _connection.query(
      markReadByPlayerSql,
      parameters: {'player_id': playerId.value, 'at': at.toUtc()},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty ? 0 : _int(value.first['marked']),
      ),
    };
  }

  @override
  Future<Result<int>> markReadBySupport({
    required SupportConversationId conversationId,
    required DateTime at,
  }) async {
    final result = await _connection.query(
      markReadBySupportSql,
      parameters: {'conversation_id': conversationId.value, 'at': at.toUtc()},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty || _int(rows.first['found']) == 0) {
      return const Result.err(SupportConversationId.notFound);
    }
    return Result.ok(_int(rows.first['marked']));
  }

  @override
  Future<Result<int>> playerUnread(UserId playerId) async {
    final result = await _connection.query(
      playerUnreadSql,
      parameters: {'player_id': playerId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        value.isEmpty ? 0 : _int(value.first['unread']),
      ),
    };
  }

  @override
  Future<Result<SupportInbox>> inbox({
    required SupportInboxFilter filter,
    required String search,
    required int limit,
  }) async {
    final listed = await _connection.query(
      inboxSql,
      parameters: {'filter': filter.name, 'search': search, 'limit': limit},
    );
    if (listed is Err<List<Map<String, dynamic>>>) {
      return Result.err(listed.error);
    }
    final counted = await _connection.query(unreadConversationsSql);
    if (counted is Err<List<Map<String, dynamic>>>) {
      return Result.err(counted.error);
    }
    final List<SupportConversationSummary> conversations = [];
    for (final Map<String, dynamic> row
        in (listed as Ok<List<Map<String, dynamic>>>).value) {
      final summary = _summary(row);
      if (summary is Err<SupportConversationSummary>) {
        return Result.err(summary.error);
      }
      conversations.add((summary as Ok<SupportConversationSummary>).value);
    }
    final countRows = (counted as Ok<List<Map<String, dynamic>>>).value;
    return Result.ok(
      SupportInbox(
        conversations: List<SupportConversationSummary>.unmodifiable(
          conversations,
        ),
        unreadConversations: countRows.isEmpty
            ? 0
            : _int(countRows.first['unread']),
      ),
    );
  }

  @override
  Future<Result<SupportConversationSummary>> conversation(
    SupportConversationId conversationId,
  ) async {
    final result = await _connection.query(
      conversationSql,
      parameters: {'conversation_id': conversationId.value},
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) return const Result.err(SupportConversationId.notFound);
    return _summary(rows.first);
  }

  @override
  Future<Result<void>> setStatus({
    required SupportConversationId conversationId,
    required SupportConversationStatus status,
    required DateTime at,
  }) async {
    final result = await _connection.query(
      setStatusSql,
      parameters: {
        'conversation_id': conversationId.value,
        'status': status.wireValue,
        'at': at.toUtc(),
      },
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) =>
        value.isEmpty
            ? const Result.err(SupportConversationId.notFound)
            : const Result.ok(null),
    };
  }

  @override
  Future<Result<List<String>>> playerPushTokens(
    SupportConversationId conversationId,
  ) async {
    final result = await _connection.query(
      playerTokensSql,
      parameters: {'conversation_id': conversationId.value},
    );
    return switch (result) {
      Err<List<Map<String, dynamic>>>(:final error) => Result.err(error),
      Ok<List<Map<String, dynamic>>>(:final value) => Result.ok(
        List<String>.unmodifiable([
          for (final row in value)
            if (row['token'] is String && (row['token'] as String).isNotEmpty)
              row['token'] as String,
        ]),
      ),
    };
  }

  Future<Result<SupportThread>> _thread({
    required String conversationId,
    required SupportConversationStatus status,
    required int unread,
    required int? beforeId,
    required int limit,
  }) async {
    final result = await _connection.query(
      messagesSql,
      parameters: {
        'conversation_id': conversationId,
        'before': beforeId,
        'limit': limit + 1,
      },
    );
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    final bool hasMore = rows.length > limit;
    final List<SupportMessage> page = [];
    for (final Map<String, dynamic> row in rows.take(limit)) {
      final message = _message(row);
      if (message is Err<SupportMessage>) return Result.err(message.error);
      page.add((message as Ok<SupportMessage>).value);
    }
    return Result.ok(
      SupportThread(
        status: status,
        unread: unread,
        messages: List<SupportMessage>.unmodifiable(page.reversed),
        hasMore: hasMore,
      ),
    );
  }

  Result<SupportMessageStored> _stored(
    Result<List<Map<String, dynamic>>> result,
    String body,
    SupportSenderRole role,
  ) {
    if (result is Err<List<Map<String, dynamic>>>) {
      return Result.err(result.error);
    }
    final rows = (result as Ok<List<Map<String, dynamic>>>).value;
    if (rows.isEmpty) return const Result.err(SupportConversationId.notFound);
    final row = rows.first;
    final Object? createdAt = row['created_at'];
    final Object? conversation = row['conversation_id'];
    if (createdAt is! DateTime || conversation is! String) {
      return Result.err(_corrupt('message', 'no time or conversation'));
    }
    return Result.ok(
      SupportMessageStored(
        conversationId: SupportConversationId(conversation),
        playerName: (row['player_name'] as String?) ?? '',
        unreadBefore: _int(row['unread_before']),
        message: SupportMessage(
          id: _int(row['id']),
          senderRole: role,
          body: body,
          createdAt: createdAt.toUtc(),
        ),
      ),
    );
  }

  static Result<SupportMessage> _message(Map<String, dynamic> row) {
    final role = SupportSenderRole.tryParse(row['sender_role'] as String?);
    final Object? createdAt = row['created_at'];
    final Object? body = row['body'];
    final Object? readAt = row['read_at'];
    if (role is Err<SupportSenderRole> ||
        createdAt is! DateTime ||
        body is! String) {
      return Result.err(_corrupt('message', 'role, time or text'));
    }
    return Result.ok(
      SupportMessage(
        id: _int(row['id']),
        senderRole: (role as Ok<SupportSenderRole>).value,
        body: body,
        createdAt: createdAt.toUtc(),
        readAt: readAt is DateTime ? readAt.toUtc() : null,
      ),
    );
  }

  static Result<SupportConversationSummary> _summary(Map<String, dynamic> row) {
    final status = SupportConversationStatus.tryParse(row['status'] as String?);
    final role = SupportSenderRole.tryParse(row['last_sender_role'] as String?);
    final Object? id = row['id'];
    final Object? player = row['player_id'];
    final Object? lastAt = row['last_message_at'];
    if (status is Err<SupportConversationStatus> ||
        role is Err<SupportSenderRole> ||
        id is! String ||
        player is! String ||
        lastAt is! DateTime) {
      return Result.err(_corrupt('conversation', 'status, side, id or time'));
    }
    return Result.ok(
      SupportConversationSummary(
        id: SupportConversationId(id),
        playerId: UserId(player),
        playerName: (row['player_name'] as String?) ?? '',
        status: (status as Ok<SupportConversationStatus>).value,
        lastMessageAt: lastAt.toUtc(),
        lastMessagePreview: (row['last_message_preview'] as String?) ?? '',
        lastSenderRole: (role as Ok<SupportSenderRole>).value,
        supportUnread: _int(row['support_unread']),
        playerUnread: _int(row['player_unread']),
      ),
    );
  }

  static int _int(Object? value) => value is int ? value : 0;

  static AppError _corrupt(String field, String detail) => AppError.transient(
    'support.row_corrupt',
    'Stored support row has invalid $field: $detail',
  );
}
