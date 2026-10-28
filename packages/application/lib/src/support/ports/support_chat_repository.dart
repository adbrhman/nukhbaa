import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One message of a support conversation (migration 0187).
final class SupportMessage {
  /// Creates the message.
  const SupportMessage({
    required this.id,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.hasImage = false,
  });

  /// Ascending with time: a page is read before the oldest id it holds.
  final int id;

  /// The side that sent it.
  final SupportSenderRole senderRole;

  /// The text.
  final String body;

  /// When it was sent.
  final DateTime createdAt;

  /// When the other side read it; null while unread.
  final DateTime? readAt;

  /// Whether a picture came with it (migration 0188); its bytes are read
  /// on their own, by the message id.
  final bool hasImage;
}

/// One page of a conversation, oldest first.
final class SupportThread {
  /// Creates the page.
  const SupportThread({
    required this.status,
    required this.unread,
    required this.messages,
    required this.hasMore,
  });

  /// The conversation's status; null when the player never wrote.
  final SupportConversationStatus? status;

  /// Messages from the other side that the reader has not read yet.
  final int unread;

  /// The page, oldest first.
  final List<SupportMessage> messages;

  /// Whether older messages are left before this page.
  final bool hasMore;
}

/// One line of the admins' support inbox.
final class SupportConversationSummary {
  /// Creates the line.
  const SupportConversationSummary({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.status,
    required this.lastMessageAt,
    required this.lastMessagePreview,
    required this.lastSenderRole,
    required this.supportUnread,
    required this.playerUnread,
  });

  /// The conversation.
  final SupportConversationId id;

  /// The player who owns it.
  final UserId playerId;

  /// The player's display name as it is now.
  final String playerName;

  /// Where it stands.
  final SupportConversationStatus status;

  /// When its last message was sent.
  final DateTime lastMessageAt;

  /// The last message, one line.
  final String lastMessagePreview;

  /// Who sent the last message.
  final SupportSenderRole lastSenderRole;

  /// The player's messages no admin has read.
  final int supportUnread;

  /// Support's messages the player has not read.
  final int playerUnread;
}

/// The admins' inbox: the conversations asked for, and how many of all of
/// them hold a player message no admin has read.
final class SupportInbox {
  /// Creates the inbox.
  const SupportInbox({
    required this.conversations,
    required this.unreadConversations,
  });

  /// The conversations, the most recent message first.
  final List<SupportConversationSummary> conversations;

  /// Conversations with an unread player message, whatever the filter.
  final int unreadConversations;
}

/// What a stored message needs to ring the other side's phone.
final class SupportMessageStored {
  /// Creates the record.
  const SupportMessageStored({
    required this.conversationId,
    required this.playerName,
    required this.message,
    required this.unreadBefore,
  });

  /// The conversation it went to.
  final SupportConversationId conversationId;

  /// The player's display name (the admins' push names him).
  final String playerName;

  /// The message as stored.
  final SupportMessage message;

  /// The other side's unread count just before this message: 0 means it
  /// is the first one waiting, the only one that rings a phone.
  final int unreadBefore;
}

/// The admins' inbox filters.
enum SupportInboxFilter {
  /// Every conversation.
  all,

  /// With a player message no admin has read.
  unread,

  /// Open.
  open,

  /// Closed or archived.
  closed;

  /// Parses `?filter=`; anything else is [all].
  static SupportInboxFilter parse(String? raw) {
    for (final SupportInboxFilter value in SupportInboxFilter.values) {
      if (value.name == raw) return value;
    }
    return SupportInboxFilter.all;
  }
}

/// Port over `support.conversations` and `support.messages` (migration
/// 0187).
///
/// General contract (Application ADR section 2): never throws, maps driver
/// failures to [ErrorKind.transient]. A conversation id that is not on
/// file answers [SupportConversationId.notFound].
abstract interface class SupportChatRepository {
  /// Stores [body] from [playerId] in his conversation, opening it on his
  /// first message and reopening it when it was closed or archived.
  Future<Result<SupportMessageStored>> addPlayerMessage({
    required UserId playerId,
    required SupportMessageBody body,
    required DateTime at,
  });

  /// Stores [body] from the admin [adminId] in [conversationId].
  Future<Result<SupportMessageStored>> addSupportReply({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportMessageBody body,
    required DateTime at,
  });

  /// [playerId]'s own conversation: at most [limit] messages before
  /// [beforeId] (the newest when null). An empty page with a null status
  /// when he never wrote.
  Future<Result<SupportThread>> playerThread({
    required UserId playerId,
    required int? beforeId,
    required int limit,
  });

  /// [conversationId] as support reads it; unread is the player's
  /// messages no admin has read.
  Future<Result<SupportThread>> conversationThread({
    required SupportConversationId conversationId,
    required int? beforeId,
    required int limit,
  });

  /// Marks support's messages to [playerId] read at [at]; answers how many.
  Future<Result<int>> markReadByPlayer({
    required UserId playerId,
    required DateTime at,
  });

  /// Marks the player's messages in [conversationId] read by support at
  /// [at]; answers how many.
  Future<Result<int>> markReadBySupport({
    required SupportConversationId conversationId,
    required DateTime at,
  });

  /// Support's messages [playerId] has not read (0 when he never wrote).
  Future<Result<int>> playerUnread(UserId playerId);

  /// The conversations that match [filter] and whose player's name holds
  /// [search] (any when empty), the most recent message first, at most
  /// [limit]; with the count of unread conversations.
  Future<Result<SupportInbox>> inbox({
    required SupportInboxFilter filter,
    required String search,
    required int limit,
  });

  /// One conversation's line, for the head of its page.
  Future<Result<SupportConversationSummary>> conversation(
    SupportConversationId conversationId,
  );

  /// Sets [conversationId]'s status.
  Future<Result<void>> setStatus({
    required SupportConversationId conversationId,
    required SupportConversationStatus status,
    required DateTime at,
  });

  /// The push tokens of [conversationId]'s player, while his account is
  /// active.
  Future<Result<List<String>>> playerPushTokens(
    SupportConversationId conversationId,
  );
}

/// Port over the pictures of `support.messages` (migration 0188).
///
/// Same contract as [SupportChatRepository]: never throws, maps driver
/// failures to [ErrorKind.transient]. A picture is stored as a message of
/// its own, with no text.
abstract interface class SupportImageRepository {
  /// Stores [image] from [playerId] in his conversation, opening or
  /// reopening it as a text message does.
  Future<Result<SupportMessageStored>> addPlayerImage({
    required UserId playerId,
    required SupportImage image,
    required DateTime at,
  });

  /// Stores [image] from the admin [adminId] in [conversationId].
  Future<Result<SupportMessageStored>> addSupportImage({
    required SupportConversationId conversationId,
    required UserId adminId,
    required SupportImage image,
    required DateTime at,
  });

  /// The picture of message [messageId] when it is in [playerId]'s own
  /// conversation; null otherwise.
  Future<Result<SupportImage?>> playerImage({
    required UserId playerId,
    required int messageId,
  });

  /// The picture of message [messageId] when it is in [conversationId];
  /// null otherwise.
  Future<Result<SupportImage?>> conversationImage({
    required SupportConversationId conversationId,
    required int messageId,
  });
}
