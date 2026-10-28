import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Pictures in the support chat (migration 0188, script 168).

const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId('11111111-0000-4000-8000-000000000001'),
  role: PlatformRole.user,
);
const AuthenticatedUser _admin = AuthenticatedUser(
  userId: UserId('11111111-0000-4000-8000-0000000000a1'),
  role: PlatformRole.admin,
);
const String _conv = '22222222-0000-4000-8000-000000000001';
final List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2];

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 28, 10);
}

final class _Images implements SupportImageRepository {
  final List<SupportImage> kept = <SupportImage>[];
  int? askedMessage;

  SupportMessageStored _stored(SupportSenderRole role) => SupportMessageStored(
    conversationId: const SupportConversationId(_conv),
    playerName: 'سامي',
    unreadBefore: 0,
    message: SupportMessage(
      id: kept.length,
      senderRole: role,
      body: '',
      createdAt: DateTime.utc(2026, 10, 28, 10),
      hasImage: true,
    ),
  );

  @override
  Future<Result<SupportMessageStored>> addPlayerImage({
    required UserId playerId,
    required SupportImage image,
    required DateTime at,
  }) async {
    kept.add(image);
    return Result.ok(_stored(SupportSenderRole.player));
  }

  @override
  Future<Result<SupportMessageStored>> addSupportImage({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportImage image,
    required DateTime at,
  }) async {
    kept.add(image);
    return Result.ok(_stored(SupportSenderRole.support));
  }

  @override
  Future<Result<SupportImage?>> playerImage({
    required UserId playerId,
    required int messageId,
  }) async {
    askedMessage = messageId;
    return Result.ok(kept.isEmpty ? null : kept.first);
  }

  @override
  Future<Result<SupportImage?>> conversationImage({
    required SupportConversationId conversationId,
    required int messageId,
  }) async => Result.ok(kept.isEmpty ? null : kept.first);
}

final class _Admins implements AdminPushTargetReader {
  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async =>
      const Result.ok(<String>['admin-phone']);
}

final class _Sender implements PushSender {
  final List<String> bodies = <String>[];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    bodies.add(body);
    return const Result.ok(<String>[]);
  }
}

final class _NoChats implements SupportChatRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not used: ${invocation.memberName}');
}

void main() {
  test('a picture is checked, stored and announced as a picture', () async {
    final _Images images = _Images();
    final _Sender sender = _Sender();
    final result = await SendSupportImage(images: images, clock: _Clock())(
      principal: _player,
      bytes: _jpeg,
      mime: 'image/jpeg',
    );
    final SupportMessageStored stored =
        (result as Ok<SupportMessageStored>).value;
    expect(images.kept.single.mime, 'image/jpeg');

    await NotifySupportMessage(
      chats: _NoChats(),
      admins: _Admins(),
      sender: sender,
    )(stored);
    expect(sender.bodies.single, 'سامي: ${SupportImage.preview}');
  });

  test('a file that is not a picture is refused before it is stored', () async {
    final _Images images = _Images();
    final result = await SendSupportImage(images: images, clock: _Clock())(
      principal: _player,
      bytes: const <int>[0x25, 0x50, 0x44, 0x46],
      mime: 'image/png',
    );
    expect(
      (result as Err<SupportMessageStored>).error.code,
      'support.image_unsupported',
    );
    expect(images.kept, isEmpty);
  });

  test(
    'only an admin answers with a picture, or reads one by conversation',
    () async {
      final _Images images = _Images();
      final refused =
          await AdminReplySupportImage(images: images, clock: _Clock())(
            principal: _player,
            conversationId: _conv,
            bytes: _jpeg,
            mime: 'image/jpeg',
          );
      expect(
        (refused as Err<SupportMessageStored>).error.code,
        'auth.insufficient_role',
      );
      final read = await AdminGetSupportImage(images: images)(
        principal: _player,
        conversationId: _conv,
        messageId: 1,
      );
      expect((read as Err<SupportImage?>).error.code, 'auth.insufficient_role');

      final sent =
          await AdminReplySupportImage(images: images, clock: _Clock())(
            principal: _admin,
            conversationId: _conv,
            bytes: _jpeg,
            mime: 'image/jpeg',
          );
      expect(sent, isA<Ok<SupportMessageStored>>());
    },
  );

  test('a message id that is not one reads no picture', () async {
    final _Images images = _Images();
    for (final int? id in <int?>[null, 0, -3]) {
      final result = await GetMySupportImage(images: images)(
        principal: _player,
        messageId: id,
      );
      expect((result as Ok<SupportImage?>).value, isNull);
    }
    expect(images.askedMessage, isNull);
    final malformed = await AdminGetSupportImage(images: images)(
      principal: _admin,
      conversationId: 'x',
      messageId: 1,
    );
    expect((malformed as Ok<SupportImage?>).value, isNull);
  });
}
