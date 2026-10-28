/// Use-cases: what was read in a support conversation (migration 0187).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// A player has read support's answers: they turn "read" on support's side
/// and his unread count is 0.
///
/// Never throws; returns how many messages it marked.
final class MarkMySupportRead {
  /// Creates the use-case over its collaborators.
  const MarkMySupportRead({
    required SupportChatRepository chats,
    required Clock clock,
  }) : _chats = chats,
       _clock = clock;

  final SupportChatRepository _chats;
  final Clock _clock;

  /// Marks [principal]'s unread answers read.
  Future<Result<int>> call({required AuthenticatedUser principal}) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    return _chats.markReadByPlayer(
      playerId: principal.userId,
      at: _clock.nowUtc(),
    );
  }
}

/// How many of support's answers a player has not read: the badge on
/// "تواصل مع المطوّر".
///
/// Never throws; returns a typed [Result].
final class GetMySupportUnread {
  /// Creates the use-case over its repository.
  const GetMySupportUnread({required SupportChatRepository chats})
    : _chats = chats;

  final SupportChatRepository _chats;

  /// Reads [principal]'s count.
  Future<Result<int>> call({required AuthenticatedUser principal}) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    return _chats.playerUnread(principal.userId);
  }
}

/// An admin has read a player's messages. Admin only.
///
/// Never throws; returns how many messages it marked.
final class AdminMarkSupportRead {
  /// Creates the use-case over its collaborators.
  const AdminMarkSupportRead({
    required SupportChatRepository chats,
    required Clock clock,
  }) : _chats = chats,
       _clock = clock;

  final SupportChatRepository _chats;
  final Clock _clock;

  /// Marks the player's messages in [conversationId] read.
  Future<Result<int>> call({
    required AuthenticatedUser principal,
    required String conversationId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final id = SupportConversationId.tryParse(conversationId);
    if (id is Err<SupportConversationId>) return Result.err(id.error);
    return _chats.markReadBySupport(
      conversationId: (id as Ok<SupportConversationId>).value,
      at: _clock.nowUtc(),
    );
  }
}
