import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The group chat's use-cases (migration 0216, script 281) over an
/// in-memory repository that keeps the adapter's rules: only a seated
/// player writes, only after the rules, never when muted.

const String _p1 = '11111111-0000-4000-8000-000000000001';
const String _p2 = '11111111-0000-4000-8000-000000000002';
const String _p3 = '11111111-0000-4000-8000-000000000003';

const AuthenticatedUser _one = AuthenticatedUser(
  userId: UserId(_p1),
  role: PlatformRole.user,
);
const AuthenticatedUser _two = AuthenticatedUser(
  userId: UserId(_p2),
  role: PlatformRole.user,
);

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 11, 15, 10);
}

final class _Msg {
  _Msg(this.id, this.sender, this.body, this.at);

  final int id;
  final String sender;
  final String body;
  final DateTime at;
  bool hidden = false;
}

final class _MemoryChats implements H2hChatRepository {
  final Set<String> seated = <String>{_p1, _p2, _p3};
  final Set<String> rules = <String>{};
  final Set<String> muted = <String>{};
  final Map<String, int> read = <String, int>{};
  final List<_Msg> messages = <_Msg>[];
  int? lastLimit;
  int _next = 1;

  @override
  Future<Result<H2hChatPage>> page({
    required UserId playerId,
    required int? afterId,
    required int limit,
  }) async {
    lastLimit = limit;
    final String me = playerId.value;
    if (!seated.contains(me)) return const Result.ok(H2hChatPage.noGroup);
    final List<_Msg> visible = <_Msg>[
      for (final _Msg m in messages)
        if (!m.hidden && (afterId == null || m.id > afterId)) m,
    ];
    final List<_Msg> newest = visible.reversed
        .take(limit)
        .toList()
        .reversed
        .toList();
    final int marker = read[me] ?? 0;
    return Result.ok(
      H2hChatPage(
        hasGroup: true,
        muted: muted.contains(me),
        rulesAccepted: rules.contains(me),
        unread: visible.where((m) => m.sender != me && m.id > marker).length,
        messages: [
          for (final _Msg m in newest)
            H2hChatMessage(
              id: m.id,
              senderId: UserId(m.sender),
              senderName: 'لاعب ${m.sender.substring(m.sender.length - 1)}',
              body: m.body,
              createdAt: m.at,
            ),
        ],
      ),
    );
  }

  @override
  Future<Result<H2hChatMessage>> send({
    required UserId playerId,
    required H2hChatBody body,
    required DateTime at,
  }) async {
    final String me = playerId.value;
    if (!seated.contains(me)) {
      return const Result.err(
        AppError.invariant('h2h.chat_no_group', 'لا توجد مجموعة'),
      );
    }
    if (muted.contains(me)) {
      return const Result.err(AppError.invariant('h2h.chat_muted', 'مُنعت'));
    }
    if (!rules.contains(me)) {
      return const Result.err(
        AppError.invariant('h2h.chat_rules_not_accepted', 'وافق أولًا'),
      );
    }
    final _Msg m = _Msg(_next++, me, body.value, at);
    messages.add(m);
    return Result.ok(
      H2hChatMessage(
        id: m.id,
        senderId: playerId,
        senderName: 'أنا',
        body: m.body,
        createdAt: at,
      ),
    );
  }

  @override
  Future<Result<void>> markRead({
    required UserId playerId,
    required DateTime at,
  }) async {
    read[playerId.value] = messages.isEmpty ? 0 : messages.last.id;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> acceptRules({
    required UserId playerId,
    required DateTime at,
  }) async {
    rules.add(playerId.value);
    return const Result.ok(null);
  }
}

void main() {
  late _MemoryChats chats;
  late H2hChat chat;

  setUp(() {
    chats = _MemoryChats();
    chat = H2hChat(chats: chats, clock: _Clock());
  });

  test('a player who accepted the rules writes, the group reads it', () async {
    await chat.acceptRules(principal: _one);
    final sent = await chat.send(principal: _one, text: '  مرحبا  ');
    expect((sent as Ok<H2hChatMessage>).value.body, 'مرحبا');

    final page = await chat.page(principal: _two);
    final H2hChatPage value = (page as Ok<H2hChatPage>).value;
    expect(value.messages.single.body, 'مرحبا');
    expect(value.unread, 1);
    expect(value.rulesAccepted, isFalse);
  });

  test('without the rules, or empty, nothing is stored', () async {
    final refused = await chat.send(principal: _one, text: 'مرحبا');
    expect(
      (refused as Err<H2hChatMessage>).error.code,
      'h2h.chat_rules_not_accepted',
    );
    await chat.acceptRules(principal: _one);
    final empty = await chat.send(principal: _one, text: '   ');
    expect((empty as Err<H2hChatMessage>).error.code, 'h2h.chat_empty_message');
    expect(chats.messages, isEmpty);
  });

  test('a muted player cannot write', () async {
    await chat.acceptRules(principal: _one);
    chats.muted.add(_p1);
    final refused = await chat.send(principal: _one, text: 'مرحبا');
    expect((refused as Err<H2hChatMessage>).error.code, 'h2h.chat_muted');
  });

  test('a page asks for 50 by default and never more than 100', () async {
    await chat.page(principal: _one);
    expect(chats.lastLimit, H2hChat.defaultLimit);
    await chat.page(principal: _one, limit: 5000);
    expect(chats.lastLimit, H2hChat.maxLimit);
    await chat.page(principal: _one, limit: 0);
    expect(chats.lastLimit, 1);
  });

  test('a player with no seat gets no group', () async {
    chats.seated.remove(_p1);
    final page = await chat.page(principal: _one);
    expect((page as Ok<H2hChatPage>).value.hasGroup, isFalse);
  });

  test('reading marks the chat read: unread is 0', () async {
    await chat.acceptRules(principal: _two);
    await chat.send(principal: _two, text: 'واحد');
    await chat.send(principal: _two, text: 'اثنان');
    expect(
      ((await chat.page(principal: _one)) as Ok<H2hChatPage>).value.unread,
      2,
    );
    await chat.markRead(principal: _one);
    expect(
      ((await chat.page(principal: _one)) as Ok<H2hChatPage>).value.unread,
      0,
    );
  });
}
