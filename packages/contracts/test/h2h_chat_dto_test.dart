import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

/// The group chat's wire shapes (migration 0216, script 281).
void main() {
  test('a page survives a round trip', () {
    const H2hChatPageDto page = H2hChatPageDto(
      hasGroup: true,
      muted: false,
      rulesAccepted: true,
      unread: 3,
      messages: <H2hChatMessageDto>[
        H2hChatMessageDto(
          id: 7,
          senderId: 'aaaaaaaa-0000-4000-8000-000000000001',
          senderName: 'سالم',
          body: 'مرحبا',
          createdAt: '2026-11-15T10:00:00.000Z',
          mine: true,
        ),
      ],
    );

    final H2hChatPageDto back = H2hChatPageDto.fromJson(page.toJson());

    expect(back.hasGroup, isTrue);
    expect(back.rulesAccepted, isTrue);
    expect(back.unread, 3);
    expect(back.messages.single.id, 7);
    expect(back.messages.single.senderName, 'سالم');
    expect(back.messages.single.mine, isTrue);
    expect(back.schemaVersion, H2hChatPageDto.currentSchemaVersion);
  });

  test('missing keys read as an empty chat without a group', () {
    final H2hChatPageDto page = H2hChatPageDto.fromJson(const {});

    expect(page.hasGroup, isFalse);
    expect(page.muted, isFalse);
    expect(page.messages, isEmpty);
    expect(page.unread, 0);
  });

  test('the acknowledgement says ok', () {
    expect(const H2hChatAckDto().toJson()['ok'], isTrue);
    expect(H2hChatAckDto.fromJson(const {}).schemaVersion, 1);
  });
}
