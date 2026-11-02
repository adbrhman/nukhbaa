import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Port: support writes first (script 202). A player's conversation is
/// opened on his first message (migration 0187); this opens it for an
/// admin who writes to a player who never wrote.
///
/// A narrow port of its own rather than a method on
/// `SupportChatRepository`, which has implementations this does not
/// concern.
///
/// MUST NOT throw; a driver failure is [ErrorKind.transient].
abstract interface class SupportConversationOpener {
  /// [playerId]'s conversation, opened when he has none. An account that
  /// does not exist is `support.player_not_found`.
  Future<Result<SupportConversationId>> openFor(UserId playerId);
}
