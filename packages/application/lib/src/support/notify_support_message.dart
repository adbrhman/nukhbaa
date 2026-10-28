/// Use-case: ring the other side's phone for a support message (migration
/// 0187).
library;

import 'package:application/src/notification/ports/admin_push_target_reader.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:application/src/support/ports/support_chat_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// After a message is stored, pushes it to the other side: a player's
/// message to every active admin, support's answer to the player.
///
/// Only the first message waiting rings ([SupportMessageStored.unreadBefore]
/// is 0): five lines typed in a row are one push, and the badge counts the
/// rest. The player's push never names the admin who answered.
///
/// Best-effort and never throws: the message is already stored.
final class NotifySupportMessage {
  /// Creates the use-case over its collaborators.
  const NotifySupportMessage({
    required SupportChatRepository chats,
    required AdminPushTargetReader admins,
    required PushSender sender,
  }) : _chats = chats,
       _admins = admins,
       _sender = sender;

  final SupportChatRepository _chats;
  final AdminPushTargetReader _admins;
  final PushSender _sender;

  /// The admins' push title.
  static const String adminTitle = 'رسالة دعم جديدة';

  /// The player's push title: support's one name.
  static const String playerTitle = 'دعم نُخبة';

  /// The longest message text a push carries.
  static const int maxPushText = 90;

  /// Pushes [stored]; answers whether a push went out.
  Future<Result<bool>> call(SupportMessageStored stored) async {
    if (stored.unreadBefore > 0) return const Result.ok(false);
    final bool fromPlayer =
        stored.message.senderRole == SupportSenderRole.player;
    final targets = fromPlayer
        ? await _admins.tokensForActiveAdmins()
        : await _chats.playerPushTokens(stored.conversationId);
    if (targets is Err<List<String>>) return Result.err(targets.error);
    final List<String> tokens = (targets as Ok<List<String>>).value;
    if (tokens.isEmpty) return const Result.ok(false);
    final String text = stored.message.body.isEmpty
        ? SupportImage.preview
        : _short(stored.message.body);
    final String name = stored.playerName.trim().isEmpty
        ? 'لاعب'
        : stored.playerName.trim();
    final sent = await _sender.send(
      tokens: tokens,
      title: fromPlayer ? adminTitle : playerTitle,
      body: fromPlayer ? '$name: $text' : text,
      link: fromPlayer ? PushLink.supportInbox : PushLink.support,
    );
    return switch (sent) {
      Ok<List<String>>() => const Result.ok(true),
      Err<List<String>>(:final error) => Result.err(error),
    };
  }

  static String _short(String body) {
    final String line = body.replaceAll(RegExp(r'\s+'), ' ');
    if (line.length <= maxPushText) return line;
    int end = maxPushText;
    // Never cut a surrogate pair in two.
    final int unit = line.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end -= 1;
    return '${line.substring(0, end)}…';
  }
}
