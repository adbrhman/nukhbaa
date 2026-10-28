import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// The support chat's wire shapes (migration 0187, script 165).
void main() {
  const SupportMessageDto answer = SupportMessageDto(
    id: 9,
    sender: 'support',
    body: 'تم الإصلاح',
    createdAt: '2026-10-28T10:00:00.000Z',
  );

  test('a message round-trips; no read time while unread', () {
    final Map<String, Object?> json = answer.toJson();
    expect(json.containsKey('read_at'), isFalse);
    final SupportMessageDto back = SupportMessageDto.fromJson(json);
    expect(back.id, 9);
    expect(back.sender, 'support');
    expect(back.body, 'تم الإصلاح');
    expect(back.readAt, isNull);
  });

  test('a thread round-trips; no status before the first message', () {
    const SupportThreadDto empty = SupportThreadDto(
      unread: 0,
      messages: <SupportMessageDto>[],
      hasMore: false,
    );
    expect(empty.toJson().containsKey('status'), isFalse);
    final SupportThreadDto back = SupportThreadDto.fromJson(
      const SupportThreadDto(
        status: 'open',
        unread: 1,
        hasMore: true,
        messages: <SupportMessageDto>[answer],
      ).toJson(),
    );
    expect(back.status, 'open');
    expect(back.unread, 1);
    expect(back.hasMore, isTrue);
    expect(back.messages.single.body, 'تم الإصلاح');
  });

  test('the inbox and a conversation page round-trip', () {
    const SupportConversationDto line = SupportConversationDto(
      id: 'c-1',
      playerId: 'p-1',
      playerName: 'سامي',
      status: 'closed',
      lastMessageAt: '2026-10-28T10:00:00.000Z',
      lastMessagePreview: 'تم',
      lastSender: 'support',
      supportUnread: 0,
      playerUnread: 1,
    );
    final SupportInboxDto inbox = SupportInboxDto.fromJson(
      const SupportInboxDto(
        conversations: <SupportConversationDto>[line],
        unreadConversations: 3,
      ).toJson(),
    );
    expect(inbox.unreadConversations, 3);
    expect(inbox.conversations.single.playerName, 'سامي');
    expect(inbox.conversations.single.lastSender, 'support');

    final SupportConversationPageDto page = SupportConversationPageDto.fromJson(
      const SupportConversationPageDto(
        conversation: line,
        thread: SupportThreadDto(
          status: 'closed',
          unread: 0,
          hasMore: false,
          messages: <SupportMessageDto>[answer],
        ),
      ).toJson(),
    );
    expect(page.conversation.playerUnread, 1);
    expect(page.thread.messages.single.id, 9);
  });

  test('missing keys read as safe defaults', () {
    final SupportInboxDto inbox = SupportInboxDto.fromJson(const {});
    expect(inbox.conversations, isEmpty);
    expect(SupportCountDto.fromJson(const {}).count, 0);
    expect(SupportSendDto.fromJson(const {}).body, '');
    expect(
      const SupportStatusDto(status: 'archived').toJson()['status'],
      'archived',
    );
  });
}
