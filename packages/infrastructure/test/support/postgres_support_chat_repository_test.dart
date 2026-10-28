import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:infrastructure/src/db/postgres_connection.dart';
import 'package:infrastructure/src/support/postgres_support_chat_repository.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const String _player = 'aaaaaaaa-0000-4000-8000-000000000001';
const String _admin = 'aaaaaaaa-0000-4000-8000-0000000000a1';
const String _conv = 'bbbbbbbb-0000-4000-8000-000000000001';

/// Answers each query with the next canned rows, and keeps what it ran.
final class _FakeConnection implements PostgresConnection {
  _FakeConnection(this._answers);

  final List<Result<List<Map<String, dynamic>>>> _answers;
  final List<String> sqls = [];
  final List<Map<String, Object?>> params = [];
  int transactions = 0;

  @override
  Future<Result<List<Map<String, dynamic>>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
  }) async {
    sqls.add(sql);
    params.add(parameters);
    return _answers.isEmpty ? const Result.ok([]) : _answers.removeAt(0);
  }

  @override
  Future<Result<bool>> ping() async => const Result.ok(true);

  @override
  Future<Result<T>> runInTransaction<T>(
    Future<Result<T>> Function(DbExecutor tx) action,
  ) async {
    transactions++;
    return action(this);
  }

  @override
  Future<void> close() async {}
}

SupportMessageBody _body(String text) =>
    (SupportMessageBody.parse(text) as Ok<SupportMessageBody>).value;

/// Hermetic tests of the support adapter's binding and row mapping; the
/// statements themselves run against Postgres in
/// supabase/tests/0187_support_chat_queries_test.sql.
void main() {
  final DateTime at = DateTime.utc(2026, 10, 28, 10);

  test('a player message opens the conversation, then stores it, in one '
      'transaction', () async {
    final connection = _FakeConnection([
      const Result.ok([]),
      Result.ok([
        {
          'id': 7,
          'conversation_id': _conv,
          'created_at': at,
          'unread_before': 0,
          'player_name': 'سامي',
        },
      ]),
    ]);

    final result = await PostgresSupportChatRepository(connection)
        .addPlayerMessage(
          playerId: const UserId(_player),
          body: _body('سطر\nثان'),
          at: at,
        );

    final SupportMessageStored stored =
        (result as Ok<SupportMessageStored>).value;
    expect(connection.transactions, 1);
    expect(connection.sqls, [
      PostgresSupportChatRepository.ensureSql,
      PostgresSupportChatRepository.playerMessageSql,
    ]);
    expect(connection.params.last, {
      'player_id': _player,
      'body': 'سطر\nثان',
      'preview': 'سطر ثان',
      'at': at,
    });
    expect(stored.conversationId.value, _conv);
    expect(stored.message.id, 7);
    expect(stored.message.senderRole, SupportSenderRole.player);
    expect(stored.unreadBefore, 0);
    expect(stored.playerName, 'سامي');
  });

  test('a reply to a conversation not on file is not found', () async {
    final connection = _FakeConnection([const Result.ok([])]);

    final result = await PostgresSupportChatRepository(connection)
        .addSupportReply(
          conversationId: const SupportConversationId(_conv),
          adminId: const UserId(_admin),
          body: _body('تم'),
          at: at,
        );

    expect(
      (result as Err<SupportMessageStored>).error.code,
      'support.conversation_not_found',
    );
    expect(connection.params.single['admin_id'], _admin);
  });

  test('a player who never wrote reads an empty page, no status', () async {
    final connection = _FakeConnection([const Result.ok([])]);

    final result = await PostgresSupportChatRepository(
      connection,
    ).playerThread(playerId: const UserId(_player), beforeId: null, limit: 30);

    final SupportThread thread = (result as Ok<SupportThread>).value;
    expect(thread.status, isNull);
    expect(thread.messages, isEmpty);
    expect(connection.sqls, hasLength(1));
  });

  test('a page asks one more row, and reads oldest first', () async {
    final connection = _FakeConnection([
      const Result.ok([
        {'id': _conv, 'status': 'open', 'unread': 1},
      ]),
      Result.ok([
        {
          'id': 9,
          'sender_role': 'support',
          'body': 'ج',
          'created_at': at,
          'read_at': null,
        },
        {
          'id': 8,
          'sender_role': 'player',
          'body': 'ب',
          'created_at': at,
          'read_at': at,
        },
        {
          'id': 7,
          'sender_role': 'player',
          'body': 'أ',
          'created_at': at,
          'read_at': at,
        },
      ]),
    ]);

    final result = await PostgresSupportChatRepository(
      connection,
    ).playerThread(playerId: const UserId(_player), beforeId: 10, limit: 2);

    final SupportThread thread = (result as Ok<SupportThread>).value;
    expect(connection.params.last, {
      'conversation_id': _conv,
      'before': 10,
      'limit': 3,
    });
    expect(thread.hasMore, isTrue);
    expect(thread.messages.map((m) => m.id), [8, 9]);
    expect(thread.messages.last.senderRole, SupportSenderRole.support);
    expect(thread.messages.last.readAt, isNull);
    expect(thread.unread, 1);
  });

  test('a stored row that cannot be true is a transient error', () async {
    final connection = _FakeConnection([
      const Result.ok([
        {'id': _conv, 'status': 'open', 'unread': 0},
      ]),
      Result.ok([
        {
          'id': 1,
          'sender_role': 'admin',
          'body': 'x',
          'created_at': at,
          'read_at': null,
        },
      ]),
    ]);

    final result = await PostgresSupportChatRepository(
      connection,
    ).playerThread(playerId: const UserId(_player), beforeId: null, limit: 30);

    expect((result as Err<SupportThread>).error.code, 'support.row_corrupt');
  });

  test(
    'the inbox binds its filter and search, and counts the unread',
    () async {
      final connection = _FakeConnection([
        Result.ok([
          {
            'id': _conv,
            'player_id': _player,
            'player_name': 'سامي',
            'status': 'open',
            'last_message_at': at,
            'last_message_preview': 'سؤال',
            'last_sender_role': 'player',
            'support_unread': 2,
            'player_unread': 0,
          },
        ]),
        const Result.ok([
          {'unread': 4},
        ]),
      ]);

      final result = await PostgresSupportChatRepository(
        connection,
      ).inbox(filter: SupportInboxFilter.unread, search: 'سا', limit: 100);

      final SupportInbox inbox = (result as Ok<SupportInbox>).value;
      expect(connection.params.first, {
        'filter': 'unread',
        'search': 'سا',
        'limit': 100,
      });
      expect(inbox.unreadConversations, 4);
      expect(inbox.conversations.single.playerName, 'سامي');
      expect(inbox.conversations.single.supportUnread, 2);
    },
  );

  test('support reads a conversation not on file: not found', () async {
    final connection = _FakeConnection([
      const Result.ok([
        {'marked': 0, 'found': 0},
      ]),
    ]);

    final result = await PostgresSupportChatRepository(connection)
        .markReadBySupport(
          conversationId: const SupportConversationId(_conv),
          at: at,
        );

    expect((result as Err<int>).error.code, 'support.conversation_not_found');
  });

  test('a status for a conversation not on file is not found', () async {
    final connection = _FakeConnection([const Result.ok([])]);

    final result = await PostgresSupportChatRepository(connection).setStatus(
      conversationId: const SupportConversationId(_conv),
      status: SupportConversationStatus.archived,
      at: at,
    );

    expect((result as Err<void>).error.code, 'support.conversation_not_found');
    expect(connection.params.single['status'], 'archived');
  });

  test('a driver failure passes through untouched', () async {
    const AppError down = AppError.transient('db.query_failed', 'down');
    final connection = _FakeConnection([const Result.err(down)]);

    final result = await PostgresSupportChatRepository(
      connection,
    ).playerUnread(const UserId(_player));

    expect((result as Err<int>).error, down);
  });
}
