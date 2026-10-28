import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The support chat's use-cases (migration 0187, script 165) over an
/// in-memory repository that keeps the adapter's rules.

const String _p1 = '11111111-0000-4000-8000-000000000001';
const String _p2 = '11111111-0000-4000-8000-000000000002';
const String _admin = '11111111-0000-4000-8000-0000000000a1';

const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId(_p1),
  role: PlatformRole.user,
);
const AuthenticatedUser _other = AuthenticatedUser(
  userId: UserId(_p2),
  role: PlatformRole.user,
);
const AuthenticatedUser _adminUser = AuthenticatedUser(
  userId: UserId(_admin),
  role: PlatformRole.admin,
);

final class _Clock implements Clock {
  DateTime now = DateTime.utc(2026, 10, 28, 10);

  @override
  DateTime nowUtc() => now;
}

final class _Admins implements AdminPushTargetReader {
  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async =>
      const Result.ok(<String>['admin-phone']);
}

final class _Sender implements PushSender {
  final List<(List<String>, String, String, String?)> sent = [];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    sent.add((tokens, title, body, link));
    return const Result.ok(<String>[]);
  }
}

/// An in-memory [SupportChatRepository] that keeps the adapter's rules
/// (migration 0187): one conversation per player, the counters of both
/// sides, a player's message reopens, pages before an id.
final class MemorySupportChats implements SupportChatRepository {
  final Map<String, _Conv> _byId = <String, _Conv>{};
  final Map<String, String> names = <String, String>{};
  final Map<String, List<String>> tokens = <String, List<String>>{};
  int _nextId = 1;
  int _nextConv = 1;

  _Conv? _ofPlayer(String player) {
    for (final _Conv c in _byId.values) {
      if (c.player == player) return c;
    }
    return null;
  }

  /// The conversation id of [player], when he wrote.
  String? conversationOf(String player) => _ofPlayer(player)?.id;

  /// Every stored message of [player]'s conversation.
  List<SupportMessage> messagesOf(String player) =>
      List<SupportMessage>.of(_ofPlayer(player)?.messages ?? const []);

  SupportMessageStored _add(
    _Conv c,
    SupportSenderRole role,
    String body,
    DateTime at,
  ) {
    final SupportMessage m = SupportMessage(
      id: _nextId++,
      senderRole: role,
      body: body,
      createdAt: at,
    );
    final int before = role == SupportSenderRole.player
        ? c.supportUnread
        : c.playerUnread;
    c.messages.add(m);
    if (role == SupportSenderRole.player) {
      c.supportUnread++;
      c.status = SupportConversationStatus.open;
    } else {
      c.playerUnread++;
    }
    c.last = m;
    return SupportMessageStored(
      conversationId: SupportConversationId(c.id),
      playerName: names[c.player] ?? '',
      message: m,
      unreadBefore: before,
    );
  }

  @override
  Future<Result<SupportMessageStored>> addPlayerMessage({
    required UserId playerId,
    required SupportMessageBody body,
    required DateTime at,
  }) async {
    _Conv? c = _ofPlayer(playerId.value);
    if (c == null) {
      final String id =
          '00000000-0000-4000-8000-${(_nextConv++).toString().padLeft(12, '0')}';
      c = _byId[id] = _Conv(id, playerId.value);
    }
    return Result.ok(_add(c, SupportSenderRole.player, body.value, at));
  }

  @override
  Future<Result<SupportMessageStored>> addSupportReply({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportMessageBody body,
    required DateTime at,
  }) async {
    final _Conv? c = _byId[conversationId.value];
    if (c == null) return const Result.err(SupportConversationId.notFound);
    return Result.ok(_add(c, SupportSenderRole.support, body.value, at));
  }

  SupportThread _thread(_Conv c, int unread, int? beforeId, int limit) {
    final List<SupportMessage> older = [
      for (final SupportMessage m in c.messages)
        if (beforeId == null || m.id < beforeId) m,
    ];
    final int start = older.length > limit ? older.length - limit : 0;
    return SupportThread(
      status: c.status,
      unread: unread,
      messages: older.sublist(start),
      hasMore: start > 0,
    );
  }

  @override
  Future<Result<SupportThread>> playerThread({
    required UserId playerId,
    required int? beforeId,
    required int limit,
  }) async {
    final _Conv? c = _ofPlayer(playerId.value);
    if (c == null) {
      return const Result.ok(
        SupportThread(
          status: null,
          unread: 0,
          messages: <SupportMessage>[],
          hasMore: false,
        ),
      );
    }
    return Result.ok(_thread(c, c.playerUnread, beforeId, limit));
  }

  @override
  Future<Result<SupportThread>> conversationThread({
    required SupportConversationId conversationId,
    required int? beforeId,
    required int limit,
  }) async {
    final _Conv? c = _byId[conversationId.value];
    if (c == null) return const Result.err(SupportConversationId.notFound);
    return Result.ok(_thread(c, c.supportUnread, beforeId, limit));
  }

  int _markRead(_Conv c, SupportSenderRole from, DateTime at) {
    int marked = 0;
    for (int i = 0; i < c.messages.length; i++) {
      final SupportMessage m = c.messages[i];
      if (m.senderRole == from && m.readAt == null) {
        c.messages[i] = SupportMessage(
          id: m.id,
          senderRole: m.senderRole,
          body: m.body,
          createdAt: m.createdAt,
          readAt: at,
        );
        marked++;
      }
    }
    return marked;
  }

  @override
  Future<Result<int>> markReadByPlayer({
    required UserId playerId,
    required DateTime at,
  }) async {
    final _Conv? c = _ofPlayer(playerId.value);
    if (c == null) return const Result.ok(0);
    c.playerUnread = 0;
    return Result.ok(_markRead(c, SupportSenderRole.support, at));
  }

  @override
  Future<Result<int>> markReadBySupport({
    required SupportConversationId conversationId,
    required DateTime at,
  }) async {
    final _Conv? c = _byId[conversationId.value];
    if (c == null) return const Result.err(SupportConversationId.notFound);
    c.supportUnread = 0;
    return Result.ok(_markRead(c, SupportSenderRole.player, at));
  }

  @override
  Future<Result<int>> playerUnread(UserId playerId) async =>
      Result.ok(_ofPlayer(playerId.value)?.playerUnread ?? 0);

  SupportConversationSummary _summary(_Conv c) => SupportConversationSummary(
    id: SupportConversationId(c.id),
    playerId: UserId(c.player),
    playerName: names[c.player] ?? '',
    status: c.status,
    lastMessageAt: c.last!.createdAt,
    lastMessagePreview: c.last!.body,
    lastSenderRole: c.last!.senderRole,
    supportUnread: c.supportUnread,
    playerUnread: c.playerUnread,
  );

  SupportInboxFilter? lastFilter;
  String? lastSearch;

  @override
  Future<Result<SupportInbox>> inbox({
    required SupportInboxFilter filter,
    required String search,
    required int limit,
  }) async {
    lastFilter = filter;
    lastSearch = search;
    final List<_Conv> all = _byId.values.where((c) => c.last != null).toList()
      ..sort((a, b) => b.last!.createdAt.compareTo(a.last!.createdAt));
    bool keep(_Conv c) => switch (filter) {
      SupportInboxFilter.all => true,
      SupportInboxFilter.unread => c.supportUnread > 0,
      SupportInboxFilter.open => c.status == SupportConversationStatus.open,
      SupportInboxFilter.closed => c.status != SupportConversationStatus.open,
    };
    return Result.ok(
      SupportInbox(
        conversations: [
          for (final _Conv c in all)
            if (keep(c) &&
                (search.isEmpty || (names[c.player] ?? '').contains(search)))
              _summary(c),
        ].take(limit).toList(),
        unreadConversations: all.where((c) => c.supportUnread > 0).length,
      ),
    );
  }

  @override
  Future<Result<SupportConversationSummary>> conversation(
    SupportConversationId conversationId,
  ) async {
    final _Conv? c = _byId[conversationId.value];
    if (c == null) return const Result.err(SupportConversationId.notFound);
    return Result.ok(_summary(c));
  }

  @override
  Future<Result<void>> setStatus({
    required SupportConversationId conversationId,
    required SupportConversationStatus status,
    required DateTime at,
  }) async {
    final _Conv? c = _byId[conversationId.value];
    if (c == null) return const Result.err(SupportConversationId.notFound);
    c.status = status;
    return const Result.ok(null);
  }

  @override
  Future<Result<List<String>>> playerPushTokens(
    SupportConversationId conversationId,
  ) async {
    final _Conv? c = _byId[conversationId.value];
    return Result.ok(
      c == null ? const <String>[] : tokens[c.player] ?? const [],
    );
  }
}

final class _Conv {
  _Conv(this.id, this.player);

  final String id;
  final String player;
  SupportConversationStatus status = SupportConversationStatus.open;
  int supportUnread = 0;
  int playerUnread = 0;
  SupportMessage? last;
  final List<SupportMessage> messages = <SupportMessage>[];
}

void main() {
  late MemorySupportChats chats;
  late _Clock clock;
  late _Sender sender;
  late NotifySupportMessage notify;

  setUp(() {
    chats = MemorySupportChats()
      ..names[_p1] = 'سامي'
      ..tokens[_p1] = <String>['player-phone'];
    clock = _Clock();
    sender = _Sender();
    notify = NotifySupportMessage(
      chats: chats,
      admins: _Admins(),
      sender: sender,
    );
  });

  Future<SupportMessageStored> send(String text) async {
    final result = await SendSupportMessage(chats: chats, clock: clock)(
      principal: _player,
      text: text,
    );
    return (result as Ok<SupportMessageStored>).value;
  }

  test('a player writes; the first message rings the admins', () async {
    final SupportMessageStored first = await send('  التطبيق لا يحفظ  ');
    expect(first.message.body, 'التطبيق لا يحفظ');
    expect(first.message.senderRole, SupportSenderRole.player);
    expect(await notify(first), const Result<bool>.ok(true));
    expect(sender.sent.single.$1, <String>['admin-phone']);
    expect(sender.sent.single.$2, 'رسالة دعم جديدة');
    expect(sender.sent.single.$3, 'سامي: التطبيق لا يحفظ');
    expect(sender.sent.single.$4, PushLink.supportInbox);

    // The second line typed before any admin read is not a second push.
    final SupportMessageStored second = await send('ما زالت');
    expect(second.unreadBefore, 1);
    expect(await notify(second), const Result<bool>.ok(false));
    expect(sender.sent, hasLength(1));
  });

  test('an empty message is refused before anything is stored', () async {
    final result = await SendSupportMessage(chats: chats, clock: clock)(
      principal: _player,
      text: '   ',
    );
    expect(
      (result as Err<SupportMessageStored>).error.code,
      'support.empty_message',
    );
    expect(chats.conversationOf(_p1), isNull);
  });

  test('a player reads only his own conversation', () async {
    await send('سؤال');
    final mine = await GetMySupportThread(chats: chats)(principal: _player);
    final theirs = await GetMySupportThread(chats: chats)(principal: _other);
    expect((mine as Ok<SupportThread>).value.messages, hasLength(1));
    expect((theirs as Ok<SupportThread>).value.messages, isEmpty);
    expect(theirs.value.status, isNull);
  });

  test('the admin side: inbox, read, answer, the player rings', () async {
    await send('سؤال');
    final String id = chats.conversationOf(_p1)!;

    final inbox = await AdminGetSupportInbox(chats: chats)(
      principal: _adminUser,
      filter: 'unread',
      search: '  سامي  ',
    );
    expect((inbox as Ok<SupportInbox>).value.conversations.single.id.value, id);
    expect(inbox.value.unreadConversations, 1);
    expect(chats.lastFilter, SupportInboxFilter.unread);
    expect(chats.lastSearch, 'سامي');

    final read = await AdminMarkSupportRead(chats: chats, clock: clock)(
      principal: _adminUser,
      conversationId: id,
    );
    expect(read, const Result<int>.ok(1));

    final reply = await AdminReplySupport(chats: chats, clock: clock)(
      principal: _adminUser,
      conversationId: id,
      text: 'تم الإصلاح',
    );
    final SupportMessageStored stored =
        (reply as Ok<SupportMessageStored>).value;
    expect(stored.message.senderRole, SupportSenderRole.support);
    expect(await notify(stored), const Result<bool>.ok(true));
    expect(sender.sent.last.$1, <String>['player-phone']);
    expect(sender.sent.last.$2, 'دعم نُخبة');
    expect(sender.sent.last.$3, 'تم الإصلاح');
    expect(sender.sent.last.$4, PushLink.support);

    final unread = await GetMySupportUnread(chats: chats)(principal: _player);
    expect(unread, const Result<int>.ok(1));
    final marked = await MarkMySupportRead(chats: chats, clock: clock)(
      principal: _player,
    );
    expect(marked, const Result<int>.ok(1));
    expect(
      await GetMySupportUnread(chats: chats)(principal: _player),
      const Result<int>.ok(0),
    );
  });

  test('a player is refused every admin use-case', () async {
    await send('سؤال');
    final String id = chats.conversationOf(_p1)!;
    final List<Result<Object?>> refused = <Result<Object?>>[
      await AdminGetSupportInbox(chats: chats)(principal: _player),
      await AdminGetSupportConversation(chats: chats)(
        principal: _player,
        conversationId: id,
      ),
      await AdminReplySupport(chats: chats, clock: clock)(
        principal: _player,
        conversationId: id,
        text: 'x',
      ),
      await AdminMarkSupportRead(chats: chats, clock: clock)(
        principal: _player,
        conversationId: id,
      ),
      await AdminSetSupportStatus(chats: chats, clock: clock)(
        principal: _player,
        conversationId: id,
        status: 'closed',
      ),
    ];
    for (final Result<Object?> r in refused) {
      expect((r as Err<Object?>).error.code, 'auth.insufficient_role');
    }
    expect(chats.messagesOf(_p1), hasLength(1));
  });

  test('a malformed or unknown conversation id is not found', () async {
    for (final String id in <String>[
      'not-a-uuid',
      '22222222-0000-4000-8000-000000000009',
    ]) {
      final reply = await AdminReplySupport(chats: chats, clock: clock)(
        principal: _adminUser,
        conversationId: id,
        text: 'x',
      );
      expect(
        (reply as Err<SupportMessageStored>).error.code,
        'support.conversation_not_found',
      );
    }
  });

  test('closing, then a new player message reopens', () async {
    await send('سؤال');
    final String id = chats.conversationOf(_p1)!;
    final closed = await AdminSetSupportStatus(chats: chats, clock: clock)(
      principal: _adminUser,
      conversationId: id,
      status: 'closed',
    );
    expect(closed, isA<Ok<void>>());
    final bad = await AdminSetSupportStatus(chats: chats, clock: clock)(
      principal: _adminUser,
      conversationId: id,
      status: 'deleted',
    );
    expect((bad as Err<void>).error.code, 'support.status_unknown');
    await send('عادت المشكلة');
    final page = await GetMySupportThread(chats: chats)(principal: _player);
    expect(
      (page as Ok<SupportThread>).value.status,
      SupportConversationStatus.open,
    );
  });

  test('pages: the newest first, older ones before an id', () async {
    for (int i = 1; i <= 5; i++) {
      await send('رسالة $i');
    }
    final newest = await GetMySupportThread(chats: chats)(
      principal: _player,
      limit: 2,
    );
    final SupportThread page = (newest as Ok<SupportThread>).value;
    expect(page.messages.map((m) => m.body), <String>['رسالة 4', 'رسالة 5']);
    expect(page.hasMore, isTrue);
    final older = await GetMySupportThread(chats: chats)(
      principal: _player,
      beforeId: page.messages.first.id,
      limit: 500,
    );
    expect(
      (older as Ok<SupportThread>).value.messages.map((m) => m.body),
      <String>['رسالة 1', 'رسالة 2', 'رسالة 3'],
    );
    expect(older.value.hasMore, isFalse);
  });

  test('a push body never carries more than 90 characters', () async {
    final SupportMessageStored long = await send('ب' * 300);
    await notify(long);
    expect(sender.sent.single.$3, 'سامي: ${'ب' * 90}…');
  });
}
