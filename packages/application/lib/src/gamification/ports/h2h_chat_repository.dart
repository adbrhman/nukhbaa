import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// One message of a group chat (migration 0216).
final class H2hChatMessage {
  /// Creates the message.
  const H2hChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  /// Ascending with time.
  final int id;

  /// The player who wrote it.
  final UserId senderId;

  /// The sender's display name as it is now.
  final String senderName;

  /// The text.
  final String body;

  /// When it was sent.
  final DateTime createdAt;
}

/// What the caller sees of his group's chat: the newest messages, oldest
/// first, with hidden messages and blocked players already left out.
final class H2hChatPage {
  /// Creates the page.
  const H2hChatPage({
    required this.hasGroup,
    required this.muted,
    required this.rulesAccepted,
    required this.unread,
    required this.messages,
  });

  /// A player with no seat in any group: no chat at all.
  static const H2hChatPage noGroup = H2hChatPage(
    hasGroup: false,
    muted: false,
    rulesAccepted: false,
    unread: 0,
    messages: <H2hChatMessage>[],
  );

  /// Whether the caller holds a seat in a group.
  final bool hasGroup;

  /// Whether an admin barred the caller from writing.
  final bool muted;

  /// Whether the caller accepted the chat rules.
  final bool rulesAccepted;

  /// Messages of others after the last one the caller read.
  final int unread;

  /// The page, oldest first.
  final List<H2hChatMessage> messages;
}

/// The chat of a head-to-head group (migration 0216): every method works on
/// the caller's own group, the newest one he sits in, never on a group id
/// the request names.
abstract interface class H2hChatRepository {
  /// The newest [limit] messages of [playerId]'s group, or those after the
  /// message id [afterId].
  Future<Result<H2hChatPage>> page({
    required UserId playerId,
    required int? afterId,
    required int limit,
  });

  /// Stores [body] from [playerId] in his group.
  Future<Result<H2hChatMessage>> send({
    required UserId playerId,
    required H2hChatBody body,
    required DateTime at,
  });

  /// [playerId] has read his group's chat up to its newest message.
  Future<Result<void>> markRead({
    required UserId playerId,
    required DateTime at,
  });

  /// [playerId] accepted the chat rules.
  Future<Result<void>> acceptRules({
    required UserId playerId,
    required DateTime at,
  });
}
