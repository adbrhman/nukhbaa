import 'dart:async';

import 'package:application/application.dart';
import 'package:contracts/contracts.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';

/// Maps the support chat's read models to their wire DTOs (migration 0187).
SupportMessageDto supportMessageDto(SupportMessage m) => SupportMessageDto(
  id: m.id,
  sender: m.senderRole.wireValue,
  body: m.body,
  createdAt: m.createdAt.toUtc().toIso8601String(),
  readAt: m.readAt?.toUtc().toIso8601String(),
  hasImage: m.hasImage,
);

/// A page of a conversation.
SupportThreadDto supportThreadDto(SupportThread t) => SupportThreadDto(
  status: t.status?.wireValue,
  unread: t.unread,
  hasMore: t.hasMore,
  messages: [for (final SupportMessage m in t.messages) supportMessageDto(m)],
);

/// One line of the admins' inbox.
SupportConversationDto supportConversationDto(SupportConversationSummary c) =>
    SupportConversationDto(
      id: c.id.value,
      playerId: c.playerId.value,
      playerName: c.playerName,
      status: c.status.wireValue,
      lastMessageAt: c.lastMessageAt.toUtc().toIso8601String(),
      lastMessagePreview: c.lastMessagePreview,
      lastSender: c.lastSenderRole.wireValue,
      supportUnread: c.supportUnread,
      playerUnread: c.playerUnread,
    );

/// Support's reading of a player's open predictions (script 261).
SupportPredictionsPeekDto supportPredictionsPeekDto(
  SupportPredictionsPeek peek,
) => SupportPredictionsPeekDto(
  predictions: [
    for (final SupportPeekedPrediction p in peek.predictions)
      SupportPeekedPredictionDto(
        fixtureId: p.fixture.value,
        homeTeam: p.homeTeam,
        awayTeam: p.awayTeam,
        kickoffAt: p.kickoffAt.toUtc().toIso8601String(),
        homeGoals: p.homeGoals,
        awayGoals: p.awayGoals,
        isDouble: p.isDouble,
        leagueName: p.leagueName,
      ),
  ],
  notice: supportMessageDto(peek.notice.message),
);

/// Rings the other side's phone for [stored], after the answer: the
/// message is already kept, so a failure here is logged and never reaches
/// the caller or the zone.
void notifySupportMessageLater(
  CompositionRoot root,
  SupportMessageStored stored,
) {
  unawaited(() async {
    try {
      final result = await root.notifySupportMessage(stored);
      if (result is Err<bool>) {
        // ignore: avoid_print
        print('support push failed: ${result.error.code}');
      }
    } on Object catch (error) {
      // ignore: avoid_print
      print('support push threw: $error');
    }
  }());
}
