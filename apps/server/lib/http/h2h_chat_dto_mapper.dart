import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Maps the group chat's read models to their wire DTOs (migration 0216).
/// [viewer] is the caller: his own messages are marked `mine`.
H2hChatMessageDto h2hChatMessageDto(H2hChatMessage m, UserId viewer) =>
    H2hChatMessageDto(
      id: m.id,
      senderId: m.senderId.value,
      senderName: m.senderName,
      body: m.body,
      createdAt: m.createdAt.toUtc().toIso8601String(),
      mine: m.senderId == viewer,
    );

/// The page of the caller's group chat.
H2hChatPageDto h2hChatPageDto(H2hChatPage p, UserId viewer) => H2hChatPageDto(
  hasGroup: p.hasGroup,
  muted: p.muted,
  rulesAccepted: p.rulesAccepted,
  unread: p.unread,
  messages: [
    for (final H2hChatMessage m in p.messages) h2hChatMessageDto(m, viewer),
  ],
);
