/// Use-cases: the admins' support inbox (migration 0187).
library;

import 'package:application/src/common/clock.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// The admins' inbox: conversations by their last message, newest first,
/// filtered and searched by the player's name. Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminGetSupportInbox {
  /// Creates the use-case over its repository.
  const AdminGetSupportInbox({required SupportChatRepository chats})
    : _chats = chats;

  final SupportChatRepository _chats;

  /// The most conversations one read lists.
  static const int maxConversations = 100;

  /// The longest name search kept; the rest is ignored.
  static const int maxSearch = 40;

  /// Reads the inbox.
  Future<Result<SupportInbox>> call({
    required AuthenticatedUser principal,
    String? filter,
    String? search,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    String term = (search ?? '').trim();
    if (term.length > maxSearch) term = term.substring(0, maxSearch);
    return _chats.inbox(
      filter: SupportInboxFilter.parse(filter),
      search: term,
      limit: maxConversations,
    );
  }
}

/// An admin closes, archives or reopens a conversation. Admin only.
///
/// Never throws; returns a typed [Result].
final class AdminSetSupportStatus {
  /// Creates the use-case over its collaborators.
  const AdminSetSupportStatus({
    required SupportChatRepository chats,
    required Clock clock,
  }) : _chats = chats,
       _clock = clock;

  final SupportChatRepository _chats;
  final Clock _clock;

  /// Sets [conversationId] to [status] (`open`, `closed` or `archived`).
  Future<Result<void>> call({
    required AuthenticatedUser principal,
    required String conversationId,
    required String? status,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final id = SupportConversationId.tryParse(conversationId);
    if (id is Err<SupportConversationId>) return Result.err(id.error);
    final parsed = SupportConversationStatus.tryParse(status);
    if (parsed is Err<SupportConversationStatus>) {
      return Result.err(parsed.error);
    }
    return _chats.setStatus(
      conversationId: (id as Ok<SupportConversationId>).value,
      status: (parsed as Ok<SupportConversationStatus>).value,
      at: _clock.nowUtc(),
    );
  }
}
