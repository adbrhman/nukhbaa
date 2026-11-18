import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/chat/index.dart' as chat;
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/chat/read/index.dart' as read;
// ignore: always_use_package_imports
import '../../routes/me/h2h-league/chat/rules/index.dart' as rules;
import 'competition_route_harness.dart';

/// The group chat's routes (migration 0216, script 281), through the real
/// handlers and use-cases over an in-memory repository that keeps the
/// adapter's rules: only a seated player writes, only after the rules,
/// never when muted.

const String _p1 = kUserId;
const String _p2 = '11111111-0000-4000-8000-000000000002';

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
  final Set<String> seated = <String>{_p1, _p2};
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

CompositionRoot _root(_MemoryChats chats) => CompositionRoot.forTesting(
  h2hChat: H2hChat(chats: chats, clock: _Clock()),
);

AuthenticatedUser _second() =>
    const AuthenticatedUser(userId: UserId(_p2), role: PlatformRole.user);

void main() {
  late _MemoryChats chats;
  late CompositionRoot root;

  setUp(() {
    chats = _MemoryChats();
    root = _root(chats);
  });

  Future<Response> write(String text, {AuthenticatedUser? as}) =>
      chat.onRequest(
        wireContext(
          root: root,
          principal: as ?? userPrincipal(),
          body: {'body': text},
        ),
      );

  Future<Response> accept({AuthenticatedUser? as}) => rules.onRequest(
    wireContext(root: root, principal: as ?? userPrincipal()),
  );

  test('the rules first, then a message the group reads', () async {
    final Response refused = await write('مرحبا');
    expect(refused.statusCode, HttpStatus.conflict);
    expect((await decodeBody(refused))['code'], 'h2h.chat_rules_not_accepted');

    expect((await accept()).statusCode, HttpStatus.ok);
    final Response sent = await write('مرحبا');
    expect(sent.statusCode, HttpStatus.created);
    final Map<String, Object?> message = await decodeBody(sent);
    expect(message['body'], 'مرحبا');
    expect(message['mine'], isTrue);

    final Response page = await chat.onRequest(
      wireContext(root: root, principal: _second(), method: HttpMethod.get),
    );
    final Map<String, Object?> json = await decodeBody(page);
    expect(page.statusCode, HttpStatus.ok);
    expect(json['has_group'], isTrue);
    expect(json['unread'], 1);
    final List<Object?> messages = json['messages']! as List<Object?>;
    expect(messages, hasLength(1));
    expect((messages.single! as Map<Object?, Object?>)['mine'], isFalse);
  });

  test('an empty message is 400 with the Arabic line', () async {
    await accept();
    final Response sent = await write('   ');
    expect(sent.statusCode, HttpStatus.badRequest);
    expect((await decodeBody(sent))['message'], 'اكتب رسالتك أولًا.');
    final Response missing = await chat.onRequest(
      wireContext(root: root, principal: userPrincipal(), body: const {}),
    );
    expect(missing.statusCode, HttpStatus.badRequest);
  });

  test('a muted player gets 409 and nothing is stored', () async {
    await accept();
    chats.muted.add(_p1);
    final Response sent = await write('مرحبا');
    expect(sent.statusCode, HttpStatus.conflict);
    expect((await decodeBody(sent))['code'], 'h2h.chat_muted');
    expect(chats.messages, isEmpty);
  });

  test('reading marks the chat read', () async {
    await accept(as: _second());
    await write('واحد', as: _second());
    final Response marked = await read.onRequest(
      wireContext(root: root, principal: userPrincipal()),
    );
    expect(marked.statusCode, HttpStatus.ok);
    final Response page = await chat.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );
    expect((await decodeBody(page))['unread'], 0);
  });

  test('a wrong method is 405', () async {
    final Response response = await read.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );
    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });
}
