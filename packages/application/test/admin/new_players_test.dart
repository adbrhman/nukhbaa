import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _player = '11111111-1111-4111-8111-111111111111';
const _conversation = '99999999-9999-4999-8999-999999999999';

AuthenticatedUser _admin() => const AuthenticatedUser(
  userId: UserId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  role: PlatformRole.admin,
);

AuthenticatedUser _user() => const AuthenticatedUser(
  userId: UserId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  role: PlatformRole.user,
);

final class _Reader implements NewPlayerReader {
  int? days;
  int? limit;

  @override
  Future<Result<List<NewPlayer>>> newPlayers({
    required int days,
    required int limit,
  }) async {
    this.days = days;
    this.limit = limit;
    return Result.ok(<NewPlayer>[
      NewPlayer(
        user: const User(
          id: UserId(_player),
          email: 'p@t.io',
          role: PlatformRole.user,
          status: UserStatus.active,
          displayName: 'ملك التوقعات',
        ),
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
  Result<SupportConversationId> answer = const Result.ok(
    SupportConversationId(_conversation),
  );

  @override
  Future<Result<SupportConversationId>> openFor(UserId playerId) async {
    opened.add(playerId.value);
    return answer;
  }
}

/// Only the reply is used here; any other call is a test failure.
final class _Chats implements SupportChatRepository {
  final List<(String, String, String)> replies = <(String, String, String)>[];

  @override
  Future<Result<SupportMessageStored>> addSupportReply({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportMessageBody body,
    required DateTime at,
  }) async {
    replies.add((conversationId.value, adminId.value, body.value));
    return const Result.err(AppError.transient('test.stop', 'stored'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 11, 2, 13);
}

/// Script 202: the admin's new-players list and his first message to a
/// player.
void main() {
  group('AdminListNewPlayers', () {
    test('an admin reads the window asked, held within 1..30 days', () async {
      final reader = _Reader();
      final list = AdminListNewPlayers(players: reader);

      final read = await list(principal: _admin(), days: 7);
      expect((read as Ok<List<NewPlayer>>).value.single.phoneAccounts, 11);
      expect(reader.days, 7);
      expect(reader.limit, AdminListNewPlayers.maxPlayers);

      await list(principal: _admin(), days: 90);
      expect(reader.days, AdminListNewPlayers.maxDays);
      await list(principal: _admin(), days: 0);
      expect(reader.days, 1);
    });

    test('a player is refused and nothing is read', () async {
      final reader = _Reader();

      final read = await AdminListNewPlayers(players: reader)(
        principal: _user(),
      );

      expect(
        (read as Err<List<NewPlayer>>).error.kind,
        ErrorKind.authorization,
      );
      expect(reader.days, isNull);
    });
  });

  group('AdminMessagePlayer', () {
    late _Opener opener;
    late _Chats chats;
    late AdminMessagePlayer message;

    setUp(() {
      opener = _Opener();
      chats = _Chats();
      message = AdminMessagePlayer(
        opener: opener,
        reply: AdminReplySupport(chats: chats, clock: _Clock()),
      );
    });

    test('opens the player\'s conversation and stores the message as '
        'support', () async {
      await message(
        principal: _admin(),
        playerId: _player,
        text: 'أرسل لنا اسمك الحقيقي',
      );

      expect(opener.opened, <String>[_player]);
      expect(chats.replies.single.$1, _conversation);
      expect(chats.replies.single.$3, 'أرسل لنا اسمك الحقيقي');
    });

    test('an empty message opens nothing', () async {
      final result = await message(
        principal: _admin(),
        playerId: _player,
        text: '   ',
      );

      expect(result, isA<Err<SupportMessageStored>>());
      expect(opener.opened, isEmpty);
      expect(chats.replies, isEmpty);
    });

    test('a malformed or unknown player is player_not_found', () async {
      final malformed = await message(
        principal: _admin(),
        playerId: 'x',
        text: 'مرحباً',
      );
      opener.answer = const Result.err(
        AppError.invariant('support.player_not_found', 'none'),
      );
      final unknown = await message(
        principal: _admin(),
        playerId: _player,
        text: 'مرحباً',
      );

      expect(
        (malformed as Err<SupportMessageStored>).error.code,
        'support.player_not_found',
      );
      expect(
        (unknown as Err<SupportMessageStored>).error.code,
        'support.player_not_found',
      );
      expect(chats.replies, isEmpty);
    });

    test('a player is refused before anything is opened', () async {
      final result = await message(
        principal: _user(),
        playerId: _player,
        text: 'مرحباً',
      );

      expect(
        (result as Err<SupportMessageStored>).error.kind,
        ErrorKind.authorization,
      );
      expect(opener.opened, isEmpty);
    });
  });
}
