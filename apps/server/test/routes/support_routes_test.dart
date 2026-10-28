import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/support/conversations/[id]/index.dart' as conv;
// ignore: always_use_package_imports
import '../../routes/admin/support/conversations/[id]/messages/index.dart'
    as reply;
// ignore: always_use_package_imports
import '../../routes/admin/support/conversations/[id]/read/index.dart'
    as admin_read;
// ignore: always_use_package_imports
import '../../routes/admin/support/conversations/index.dart' as inbox;
// ignore: always_use_package_imports
import '../../routes/me/support/messages/index.dart' as messages;
// ignore: always_use_package_imports
import '../../routes/me/support/read/index.dart' as my_read;
// ignore: always_use_package_imports
import '../../routes/me/support/unread/index.dart' as unread;
import 'competition_route_harness.dart';

/// The support chat's routes (migration 0187, script 165), through the real
/// handlers and use-cases over an in-memory repository.

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 28, 10);
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

CompositionRoot _root(MemorySupportChats chats, _Sender sender) {
  final _Clock clock = _Clock();
  return CompositionRoot.forTesting(
    sendSupportMessage: SendSupportMessage(chats: chats, clock: clock),
    getMySupportThread: GetMySupportThread(chats: chats),
    markMySupportRead: MarkMySupportRead(chats: chats, clock: clock),
    getMySupportUnread: GetMySupportUnread(chats: chats),
    adminGetSupportInbox: AdminGetSupportInbox(chats: chats),
    adminGetSupportConversation: AdminGetSupportConversation(chats: chats),
    adminReplySupport: AdminReplySupport(chats: chats, clock: clock),
    adminMarkSupportRead: AdminMarkSupportRead(chats: chats, clock: clock),
    adminSetSupportStatus: AdminSetSupportStatus(chats: chats, clock: clock),
    notifySupportMessage: NotifySupportMessage(
      chats: chats,
      admins: _Admins(),
      sender: sender,
    ),
  );
}

/// Lets the push that a route starts after answering run.
Future<void> _settle() async {
  for (int i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MemorySupportChats chats;
  late _Sender sender;
  late CompositionRoot root;

  setUp(() {
    chats = MemorySupportChats()
      ..names[kUserId] = 'سامي'
      ..tokens[kUserId] = <String>['player-phone'];
    sender = _Sender();
    root = _root(chats, sender);
  });

  Future<Response> playerSends(String body) => messages.onRequest(
    wireContext(root: root, principal: userPrincipal(), body: {'body': body}),
  );

  test('a player writes, the admins are rung, he reads his page', () async {
    final Response sent = await playerSends('التطبيق لا يحفظ توقعي');
    expect(sent.statusCode, HttpStatus.created);
    final Map<String, Object?> message = await decodeBody(sent);
    expect(message['sender'], 'player');
    expect(message['body'], 'التطبيق لا يحفظ توقعي');
    await _settle();
    expect(sender.sent.single.$1, <String>['admin-phone']);
    expect(sender.sent.single.$4, 'support_inbox');

    final Response page = await messages.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );
    final Map<String, Object?> json = await decodeBody(page);
    expect(page.statusCode, HttpStatus.ok);
    expect(json['status'], 'open');
    expect((json['messages']! as List<Object?>), hasLength(1));
  });

  test('an empty message is 400 with the Arabic line', () async {
    final Response sent = await playerSends('   ');
    expect(sent.statusCode, HttpStatus.badRequest);
    expect((await decodeBody(sent))['message'], 'اكتب رسالتك أولًا.');
    final Response missing = await messages.onRequest(
      wireContext(root: root, principal: userPrincipal(), body: const {}),
    );
    expect(missing.statusCode, HttpStatus.badRequest);
  });

  test('another player reads nothing of it', () async {
    await playerSends('سري');
    final Response page = await messages.onRequest(
      wireContext(
        root: root,
        principal: const AuthenticatedUser(
          userId: UserId('99999999-9999-4999-8999-999999999999'),
          role: PlatformRole.user,
        ),
        method: HttpMethod.get,
        // A conversation id in the query changes nothing: his own only.
        queryParameters: {'conversation': chats.conversationOf(kUserId)!},
      ),
    );
    final Map<String, Object?> json = await decodeBody(page);
    expect(json['messages'], isEmpty);
    expect(json.containsKey('status'), isFalse);
  });

  test('a player is refused every admin route', () async {
    await playerSends('سؤال');
    final String id = chats.conversationOf(kUserId)!;
    final List<Response> refused = <Response>[
      await inbox.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      ),
      await conv.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
        id,
      ),
      await conv.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          method: HttpMethod.patch,
          body: {'status': 'closed'},
        ),
        id,
      ),
      await reply.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          body: {'body': 'أنا الدعم'},
        ),
        id,
      ),
      await admin_read.onRequest(
        wireContext(root: root, principal: userPrincipal()),
        id,
      ),
    ];
    for (final Response r in refused) {
      expect(r.statusCode, HttpStatus.unauthorized);
      expect((await decodeBody(r))['code'], 'auth.insufficient_role');
    }
    expect(chats.messagesOf(kUserId), hasLength(1));
  });

  test('an admin reads the inbox, opens, reads, answers, closes', () async {
    await playerSends('سؤال عن النقاط');
    final String id = chats.conversationOf(kUserId)!;

    final Response listed = await inbox.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
        queryParameters: {'filter': 'unread', 'search': 'سامي'},
      ),
    );
    final Map<String, Object?> box = await decodeBody(listed);
    expect(box['unread_conversations'], 1);
    final Map<Object?, Object?> line =
        (box['conversations']! as List<Object?>).single!
            as Map<Object?, Object?>;
    expect(line['id'], id);
    expect(line['player_name'], 'سامي');
    expect(line['support_unread'], 1);

    final Response opened = await conv.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
      id,
    );
    final Map<String, Object?> page = await decodeBody(opened);
    expect((page['conversation']! as Map<Object?, Object?>)['status'], 'open');
    expect(
      ((page['thread']! as Map<Object?, Object?>)['messages']! as List<Object?>)
          .length,
      1,
    );

    final Response read = await admin_read.onRequest(
      wireContext(root: root, principal: adminPrincipal()),
      id,
    );
    expect((await decodeBody(read))['count'], 1);

    sender.sent.clear();
    final Response answered = await reply.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        body: {'body': 'النقاط تُحسب بعد نهاية المباراة'},
      ),
      id,
    );
    expect(answered.statusCode, HttpStatus.created);
    expect((await decodeBody(answered))['sender'], 'support');
    await _settle();
    expect(sender.sent.single.$1, <String>['player-phone']);
    expect(sender.sent.single.$2, 'دعم نُخبة');
    expect(sender.sent.single.$4, 'support');

    final Response count = await unread.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );
    expect((await decodeBody(count))['count'], 1);
    final Response mine = await my_read.onRequest(
      wireContext(root: root, principal: userPrincipal()),
    );
    expect((await decodeBody(mine))['count'], 1);

    final Response closed = await conv.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.patch,
        body: {'status': 'closed'},
      ),
      id,
    );
    expect((await decodeBody(closed))['status'], 'closed');
  });

  test('a conversation not on file is 409; a bad status is 400', () async {
    final Response missing = await reply.onRequest(
      wireContext(root: root, principal: adminPrincipal(), body: {'body': 'x'}),
      'not-a-uuid',
    );
    expect(missing.statusCode, HttpStatus.conflict);
    expect(
      (await decodeBody(missing))['code'],
      'support.conversation_not_found',
    );

    await playerSends('سؤال');
    final Response bad = await conv.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.patch,
        body: {'status': 'deleted'},
      ),
      chats.conversationOf(kUserId)!,
    );
    expect(bad.statusCode, HttpStatus.badRequest);
  });

  test('other methods are 405', () async {
    final List<Response> wrong = <Response>[
      await messages.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          method: HttpMethod.delete,
        ),
      ),
      await my_read.onRequest(
        wireContext(
          root: root,
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      ),
      await unread.onRequest(
        wireContext(root: root, principal: userPrincipal()),
      ),
      await inbox.onRequest(
        wireContext(root: root, principal: adminPrincipal()),
      ),
    ];
    for (final Response r in wrong) {
      expect(r.statusCode, HttpStatus.methodNotAllowed);
    }
  });

  // Last: it spends the player's hourly allowance for this isolate.
  test('a player may send 60 messages an hour, then 429', () async {
    int created = 0;
    Response last = await playerSends('1');
    for (int i = 0; i < 70 && last.statusCode == HttpStatus.created; i++) {
      created++;
      last = await playerSends('رسالة $i');
    }
    expect(last.statusCode, HttpStatus.tooManyRequests);
    expect(created, lessThanOrEqualTo(60));
  });
}
