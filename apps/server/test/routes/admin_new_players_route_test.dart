import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/new-players/index.dart' as new_players;
// ignore: always_use_package_imports
import '../../routes/admin/support/players/[id]/messages/index.dart'
    as message_player;
import 'competition_route_harness.dart';

const _conversation = '99999999-9999-4999-8999-999999999999';

final class _Reader implements NewPlayerReader {
  _Reader({this.name = 'Human'});

  final String name;
  int? days;

  @override
  Future<Result<List<NewPlayer>>> newPlayers({
    required int days,
    required int limit,
  }) async {
    this.days = days;
    return Result.ok(<NewPlayer>[
      NewPlayer(
        user: storedUser().copyWith(displayName: name),
        joinedAt: DateTime.utc(2026, 11, 2, 12),
        phoneAccounts: 11,
        predictions: 10,
        nameHint: NewPlayerNameHint.title,
      ),
    ]);
  }
}

final class _Opener implements SupportConversationOpener {
  final List<String> opened = <String>[];

  @override
  Future<Result<SupportConversationId>> openFor(UserId playerId) async {
    opened.add(playerId.value);
    return const Result.ok(SupportConversationId(_conversation));
  }
}

final class _Chats implements SupportChatRepository {
  final List<String> bodies = <String>[];

  @override
  Future<Result<SupportMessageStored>> addSupportReply({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportMessageBody body,
    required DateTime at,
  }) async {
    bodies.add(body.value);
    return Result.ok(
      SupportMessageStored(
        conversationId: conversationId,
        playerName: 'Human',
        message: SupportMessage(
          id: 1,
          senderRole: SupportSenderRole.support,
          body: body.value,
          createdAt: at,
        ),
        unreadBefore: 0,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

/// Every account's name: the new player himself and one like him.
final class _Names implements AccountNameDirectory {
  const _Names();

  @override
  Future<Result<List<AccountName>>> all() async =>
      const Result.ok(<AccountName>[
        AccountName(
          id: UserId(kTargetUserId),
          displayName: 'عبدالرحمن المغربي',
        ),
        AccountName(
          id: UserId('d1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1'),
          displayName: 'عبد الرحمن محمد المغربي',
        ),
        AccountName(
          id: UserId('d2d2d2d2-d2d2-4d2d-8d2d-d2d2d2d2d2d2'),
          displayName: 'عبدالله المغربي',
        ),
      ]);
}

/// Script 202: the admin's new-players list and his first message, through
/// the real wiring.
void main() {
  group('GET /admin/new-players', () {
    Future<Response> list(
      AuthenticatedUser principal, {
      _Reader? reader,
      Map<String, String> query = const {},
      bool wired = true,
      AccountNameDirectory? names,
    }) => new_players.onRequest(
      wireContext(
        root: CompositionRoot.forTesting(
          adminListNewPlayers: wired
              ? AdminListNewPlayers(players: reader ?? _Reader(), names: names)
              : null,
        ),
        principal: principal,
        method: HttpMethod.get,
        queryParameters: query,
      ),
    );

    test('an admin reads each player, his phone and his hint', () async {
      final reader = _Reader();

      final response = await list(
        adminPrincipal(),
        reader: reader,
        query: const {'days': '3'},
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['days'], 3);
      final player = ((body['players']! as List<Object?>).single! as Map)
          .cast<String, Object?>();
      expect(player['phone_accounts'], 11);
      expect(player['predictions'], 10);
      expect(player['name_hint'], 'title');
      expect(player['joined_at'], '2026-11-02T12:00:00.000Z');
      expect((player['user']! as Map)['id'], kTargetUserId);
      expect(reader.days, 3);
    });

    test('each player carries the names like his (script 263)', () async {
      final response = await list(
        adminPrincipal(),
        reader: _Reader(name: 'عبدالرحمن المغربي'),
        names: const _Names(),
      );

      final player =
          ((await decodeBody(response))['players']! as List<Object?>).single!
              as Map;
      expect(player['similar_to'], <Object?>['عبد الرحمن محمد المغربي']);
    });

    test('no window asked is 7 days', () async {
      final reader = _Reader();

      await list(adminPrincipal(), reader: reader);

      expect(reader.days, 7);
    });

    test('a player is refused and nothing is read', () async {
      final reader = _Reader();

      final response = await list(userPrincipal(), reader: reader);

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(reader.days, isNull);
    });

    test('an unwired root is 503', () async {
      final response = await list(adminPrincipal(), wired: false);

      expect(response.statusCode, HttpStatus.serviceUnavailable);
    });
  });

  group('POST /admin/support/players/{id}/messages', () {
    late _Opener opener;
    late _Chats chats;

    Future<Response> send(AuthenticatedUser principal, Object? body) {
      opener = _Opener();
      chats = _Chats();
      return message_player.onRequest(
        wireContext(
          root: CompositionRoot.forTesting(
            adminMessagePlayer: AdminMessagePlayer(
              opener: opener,
              reply: AdminReplySupport(
                chats: chats,
                clock: FixedClock(DateTime.utc(2026, 11, 2, 13)),
              ),
            ),
          ),
          principal: principal,
          body: body,
        ),
        kTargetUserId,
      );
    }

    test('an admin writes first: the conversation is opened, 201', () async {
      final response = await send(adminPrincipal(), {
        'body': 'أرسل لنا اسمك الحقيقي',
      });

      expect(response.statusCode, HttpStatus.created);
      final body = await decodeBody(response);
      expect(body['sender'], 'support');
      expect(body['body'], 'أرسل لنا اسمك الحقيقي');
      expect(opener.opened, <String>[kTargetUserId]);
      expect(chats.bodies, <String>['أرسل لنا اسمك الحقيقي']);
    });

    test('a missing body is 400 and nothing is opened', () async {
      final response = await send(adminPrincipal(), const <String, Object?>{});

      expect(response.statusCode, HttpStatus.badRequest);
      expect(opener.opened, isEmpty);
    });

    test('a player is refused', () async {
      final response = await send(userPrincipal(), {'body': 'مرحباً'});

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(opener.opened, isEmpty);
    });
  });
}
