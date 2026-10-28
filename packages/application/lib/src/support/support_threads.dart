/// Use-cases: reading a support conversation (migration 0187).
library;

import 'package:application/src/identity/authorization.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The page size when none (or a nonsense one) is asked for.
const int supportDefaultPage = 30;

/// The largest page a read may ask for.
const int supportMaxPage = 100;

int _pageSize(int? limit) => limit == null || limit < 1
    ? supportDefaultPage
    : (limit > supportMaxPage ? supportMaxPage : limit);

int? _before(int? beforeId) =>
    beforeId == null || beforeId < 1 ? null : beforeId;

/// A player reads his own conversation with support, newest page first
/// (older pages before a message id). Only his: the repository is asked by
/// his own id, never by a conversation id from the request.
///
/// Never throws; returns a typed [Result].
final class GetMySupportThread {
  /// Creates the use-case over its repository.
  const GetMySupportThread({required SupportChatRepository chats})
    : _chats = chats;

  final SupportChatRepository _chats;

  /// Reads [principal]'s page.
  Future<Result<SupportThread>> call({
    required AuthenticatedUser principal,
    int? beforeId,
    int? limit,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    return _chats.playerThread(
      playerId: principal.userId,
      beforeId: _before(beforeId),
      limit: _pageSize(limit),
    );
  }
}

/// One conversation as an admin opens it: its line and a page of it.
final class SupportConversationPage {
  /// Creates the page.
  const SupportConversationPage({required this.summary, required this.thread});

  /// The conversation's line (player, status, counters).
  final SupportConversationSummary summary;

  /// The page, oldest first.
  final SupportThread thread;
}

/// An admin reads one player's conversation. Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminGetSupportConversation {
  /// Creates the use-case over its repository.
  const AdminGetSupportConversation({required SupportChatRepository chats})
    : _chats = chats;

  final SupportChatRepository _chats;

  /// Reads [conversationId].
  Future<Result<SupportConversationPage>> call({
    required AuthenticatedUser principal,
    required String conversationId,
    int? beforeId,
    int? limit,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final parsed = SupportConversationId.tryParse(conversationId);
    if (parsed is Err<SupportConversationId>) return Result.err(parsed.error);
    final SupportConversationId id =
        (parsed as Ok<SupportConversationId>).value;
    final summary = await _chats.conversation(id);
    if (summary is Err<SupportConversationSummary>) {
      return Result.err(summary.error);
    }
    final thread = await _chats.conversationThread(
      conversationId: id,
      beforeId: _before(beforeId),
      limit: _pageSize(limit),
    );
    return switch (thread) {
      Err<SupportThread>(:final error) => Result.err(error),
      Ok<SupportThread>(:final value) => Result.ok(
        SupportConversationPage(
          summary: (summary as Ok<SupportConversationSummary>).value,
          thread: value,
        ),
      ),
    };
  }
}
