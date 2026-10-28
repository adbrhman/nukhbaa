import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/support/conversations/[id]/images/index.dart'
    as admin_send;
// ignore: always_use_package_imports
import '../../routes/admin/support/conversations/[id]/messages/[messageId]/image/index.dart'
    as admin_read;
// ignore: always_use_package_imports
import '../../routes/me/support/images/index.dart' as send;
// ignore: always_use_package_imports
import '../../routes/me/support/messages/[id]/image/index.dart' as read;
import 'competition_route_harness.dart';

/// Pictures in the support chat (migration 0188, script 168), through the
/// real handlers and use-cases over an in-memory repository.

const String _conv = 'aaaaaaaa-0000-4000-8000-000000000001';
const String _otherConv = 'aaaaaaaa-0000-4000-8000-000000000002';
final List<int> _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4];

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 10, 28, 10);
}

final class _Images implements SupportImageRepository {
  /// message id -> (conversation, owner, picture)
  final Map<int, (String, String, SupportImage)> stored =
      <int, (String, String, SupportImage)>{};
  int _next = 1;

  SupportMessageStored _keep(
    String conv,
    String owner,
    SupportImage image,
    SupportSenderRole role,
    DateTime at,
  ) {
    final int id = _next++;
    stored[id] = (conv, owner, image);
    return SupportMessageStored(
      conversationId: SupportConversationId(conv),
      playerName: 'سامي',
      unreadBefore: 1,
      message: SupportMessage(
        id: id,
        senderRole: role,
        body: '',
        createdAt: at,
        hasImage: true,
      ),
    );
  }

  @override
  Future<Result<SupportMessageStored>> addPlayerImage({
    required UserId playerId,
    required SupportImage image,
    required DateTime at,
  }) async => Result.ok(
    _keep(_conv, playerId.value, image, SupportSenderRole.player, at),
  );

  @override
  Future<Result<SupportMessageStored>> addSupportImage({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportImage image,
    required DateTime at,
  }) async => Result.ok(
    _keep(conversationId.value, kUserId, image, SupportSenderRole.support, at),
  );

  @override
  Future<Result<SupportImage?>> playerImage({
    required UserId playerId,
    required int messageId,
  }) async {
    final (String, String, SupportImage)? row = stored[messageId];
    return Result.ok(row != null && row.$2 == playerId.value ? row.$3 : null);
  }

  @override
  Future<Result<SupportImage?>> conversationImage({
    required SupportConversationId conversationId,
    required int messageId,
  }) async {
    final (String, String, SupportImage)? row = stored[messageId];
    return Result.ok(
      row != null && row.$1 == conversationId.value ? row.$3 : null,
    );
  }
}

/// A request whose body is raw bytes under [contentType].
RequestContext _bytesContext(
  CompositionRoot root,
  AuthenticatedUser principal, {
  required List<int> bytes,
  String? contentType,
  HttpMethod method = HttpMethod.post,
}) {
  final request = MockRequest();
  when(() => request.method).thenReturn(method);
  when(
    () => request.headers,
  ).thenReturn(<String, String>{HttpHeaders.contentTypeHeader: ?contentType});
  when(request.bytes).thenAnswer((_) => Stream<List<int>>.value(bytes));
  when(() => request.uri).thenReturn(Uri(path: '/'));
  final context = MockRequestContext();
  final Future<CompositionRoot> rootFuture = Future<CompositionRoot>.value(
    root,
  );
  when(() => context.request).thenReturn(request);
  when(
    () => context.read<Future<CompositionRoot>>(),
  ).thenAnswer((_) => rootFuture);
  when(() => context.read<AuthenticatedUser>()).thenReturn(principal);
  return context;
}

void main() {
  late _Images images;
  late CompositionRoot root;

  setUp(() {
    images = _Images();
    final _Clock clock = _Clock();
    root = CompositionRoot.forTesting(
      sendSupportImage: SendSupportImage(images: images, clock: clock),
      getMySupportImage: GetMySupportImage(images: images),
      adminReplySupportImage: AdminReplySupportImage(
        images: images,
        clock: clock,
      ),
      adminGetSupportImage: AdminGetSupportImage(images: images),
      notifySupportMessage: NotifySupportMessage(
        chats: MemoryNoChats(),
        admins: _NoAdmins(),
        sender: const _NoPush(),
      ),
    );
  });

  test('a player sends a picture; it reads back only for him', () async {
    final Response sent = await send.onRequest(
      _bytesContext(
        root,
        userPrincipal(),
        bytes: _jpeg,
        contentType: 'image/jpeg',
      ),
    );
    expect(sent.statusCode, HttpStatus.created);
    final Map<String, Object?> message = await decodeBody(sent);
    expect(message['has_image'], true);
    expect(message['body'], '');

    final Response mine = await read.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
      '${message['id']}',
    );
    expect(mine.statusCode, HttpStatus.ok);
    expect(mine.headers[HttpHeaders.contentTypeHeader], 'image/jpeg');
    expect(await mine.bytes().expand((b) => b).toList(), _jpeg);

    final Response theirs = await read.onRequest(
      wireContext(
        root: root,
        principal: const AuthenticatedUser(
          userId: UserId('99999999-9999-4999-8999-999999999999'),
          role: PlatformRole.user,
        ),
        method: HttpMethod.get,
      ),
      '${message['id']}',
    );
    expect(theirs.statusCode, HttpStatus.notFound);
  });

  test('a file that is not the picture it claims is 400', () async {
    final Response pdf = await send.onRequest(
      _bytesContext(
        root,
        userPrincipal(),
        bytes: <int>[0x25, 0x50, 0x44, 0x46, 1, 2],
        contentType: 'image/jpeg',
      ),
    );
    expect(pdf.statusCode, HttpStatus.badRequest);
    expect((await decodeBody(pdf))['code'], 'support.image_unsupported');
    final Response big = await send.onRequest(
      _bytesContext(
        root,
        userPrincipal(),
        bytes: <int>[..._jpeg, ...List<int>.filled(512 * 1024, 0)],
        contentType: 'image/jpeg',
      ),
    );
    expect(big.statusCode, HttpStatus.badRequest);
    expect((await decodeBody(big))['code'], 'support.image_too_large');
    expect(images.stored, isEmpty);
  });

  test('an admin answers with a picture; a player is refused it', () async {
    final Response sent = await admin_send.onRequest(
      _bytesContext(
        root,
        adminPrincipal(),
        bytes: _jpeg,
        contentType: 'image/jpeg',
      ),
      _conv,
    );
    expect(sent.statusCode, HttpStatus.created);
    final int id = (await decodeBody(sent))['id']! as int;

    final Response ok = await admin_read.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
      _conv,
      '$id',
    );
    expect(ok.statusCode, HttpStatus.ok);
    final Response elsewhere = await admin_read.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
      _otherConv,
      '$id',
    );
    expect(elsewhere.statusCode, HttpStatus.notFound);

    final Response player = await admin_send.onRequest(
      _bytesContext(
        root,
        userPrincipal(),
        bytes: _jpeg,
        contentType: 'image/jpeg',
      ),
      _conv,
    );
    expect(player.statusCode, HttpStatus.unauthorized);
    final Response playerRead = await admin_read.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
      _conv,
      '$id',
    );
    expect(playerRead.statusCode, HttpStatus.unauthorized);
  });

  // Last: it spends the player's daily allowance for this isolate.
  test('a player may send 20 pictures a day, then 429', () async {
    Response last = await send.onRequest(
      _bytesContext(
        root,
        userPrincipal(),
        bytes: _jpeg,
        contentType: 'image/jpeg',
      ),
    );
    for (int i = 0; i < 25 && last.statusCode == HttpStatus.created; i++) {
      last = await send.onRequest(
        _bytesContext(
          root,
          userPrincipal(),
          bytes: _jpeg,
          contentType: 'image/jpeg',
        ),
      );
    }
    expect(last.statusCode, HttpStatus.tooManyRequests);
  });
}

final class _NoAdmins implements AdminPushTargetReader {
  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async =>
      const Result.ok(<String>[]);
}

final class _NoPush implements PushSender {
  const _NoPush();

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async => const Result.ok(<String>[]);
}

/// The push after a picture asks the chat repository only for a player's
/// phones; there are none here.
final class MemoryNoChats implements SupportChatRepository {
  @override
  Future<Result<List<String>>> playerPushTokens(
    SupportConversationId conversationId,
  ) async => const Result.ok(<String>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not used: ${invocation.memberName}');
}
