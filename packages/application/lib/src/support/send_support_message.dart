/// Use-cases: a message in a support conversation, from the player or from
/// support (migration 0187).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A player writes to Nukhbaa support. His first message opens his one
/// conversation; a message to a closed or archived one reopens it.
///
/// Never throws; returns a typed [Result].
final class SendSupportMessage {
  /// Creates the use-case over its collaborators.
  const SendSupportMessage({
    required SupportChatRepository chats,
    required Clock clock,
  }) : _chats = chats,
       _clock = clock;

  final SupportChatRepository _chats;
  final Clock _clock;

  /// Stores [text] from [principal].
  Future<Result<SupportMessageStored>> call({
    required AuthenticatedUser principal,
    required String? text,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final body = SupportMessageBody.parse(text);
    if (body is Err<SupportMessageBody>) return Result.err(body.error);
    return _chats.addPlayerMessage(
      playerId: principal.userId,
      body: (body as Ok<SupportMessageBody>).value,
      at: _clock.nowUtc(),
    );
  }
}

/// An admin answers a player as Nukhbaa support. Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminReplySupport {
  /// Creates the use-case over its collaborators.
  const AdminReplySupport({
    required SupportChatRepository chats,
    required Clock clock,
  }) : _chats = chats,
       _clock = clock;

  final SupportChatRepository _chats;
  final Clock _clock;

  /// Stores [text] from [principal] in [conversationId].
  Future<Result<SupportMessageStored>> call({
    required AuthenticatedUser principal,
    required String conversationId,
    required String? text,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final id = SupportConversationId.tryParse(conversationId);
    if (id is Err<SupportConversationId>) return Result.err(id.error);
    final body = SupportMessageBody.parse(text);
    if (body is Err<SupportMessageBody>) return Result.err(body.error);
    return _chats.addSupportReply(
      conversationId: (id as Ok<SupportConversationId>).value,
      adminId: principal.userId,
      body: (body as Ok<SupportMessageBody>).value,
      at: _clock.nowUtc(),
    );
  }
}
