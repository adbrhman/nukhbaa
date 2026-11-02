import 'package:application/src/identity/authorization.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:application/src/support/ports/support_conversation_opener.dart';
import 'package:application/src/support/send_support_message.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// An admin writes first to a player as Nukhbaa support (script 202):
/// from the new-players screen, to ask a player for his real name. The
/// player's conversation is opened when he never wrote, then the message
/// is stored as any support reply ([AdminReplySupport]).
///
/// Admin only. The text is checked before anything is opened, so a refused
/// message opens no conversation. Never throws; returns a typed [Result].
final class AdminMessagePlayer {
  /// Creates the use-case over its collaborators.
  const AdminMessagePlayer({
    required SupportConversationOpener opener,
    required AdminReplySupport reply,
  }) : _opener = opener,
       _reply = reply;

  final SupportConversationOpener _opener;
  final AdminReplySupport _reply;

  /// Stores [text] from the admin [principal] in [playerId]'s conversation.
  Future<Result<SupportMessageStored>> call({
    required AuthenticatedUser principal,
    required String playerId,
    required String? text,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.admin);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    final player = UserId.tryParse(playerId);
    if (player is Err<UserId>) {
      return const Result.err(
        AppError.invariant('support.player_not_found', 'الحساب غير موجود.'),
      );
    }
    final body = SupportMessageBody.parse(text);
    if (body is Err<SupportMessageBody>) return Result.err(body.error);
    final opened = await _opener.openFor((player as Ok<UserId>).value);
    if (opened is Err<SupportConversationId>) {
      return Result.err(opened.error);
    }
    return _reply(
      principal: principal,
      conversationId: (opened as Ok<SupportConversationId>).value.value,
      text: text,
    );
  }
}
