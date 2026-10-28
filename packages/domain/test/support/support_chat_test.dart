import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The support chat's value types (migration 0187, script 165).
void main() {
  group('SupportMessageBody', () {
    test('keeps the trimmed text', () {
      final body = SupportMessageBody.parse('  التطبيق لا يفتح \n');
      expect((body as Ok<SupportMessageBody>).value.value, 'التطبيق لا يفتح');
    });

    test('refuses nothing typed, in Arabic', () {
      for (final String? raw in <String?>[null, '', '   ', '\n\t']) {
        final body = SupportMessageBody.parse(raw);
        expect(body, isA<Err<SupportMessageBody>>());
        final AppError error = (body as Err<SupportMessageBody>).error;
        expect(error.code, 'support.empty_message');
        expect(error.message, 'اكتب رسالتك أولًا.');
      }
    });

    test('2000 characters pass, 2001 are refused', () {
      expect(
        SupportMessageBody.parse('x' * 2000),
        isA<Ok<SupportMessageBody>>(),
      );
      final long = SupportMessageBody.parse('x' * 2001);
      expect(
        (long as Err<SupportMessageBody>).error.code,
        'support.message_too_long',
      );
    });

    test('the preview is one line of at most 120 characters', () {
      final body =
          (SupportMessageBody.parse('سطر أول\n\nسطر   ثان')
                  as Ok<SupportMessageBody>)
              .value;
      expect(body.preview, 'سطر أول سطر ثان');
      final long =
          (SupportMessageBody.parse('ب' * 300) as Ok<SupportMessageBody>).value;
      expect(long.preview.length, 120);
    });

    test('the preview never cuts an emoji in two', () {
      final String text = '${'a' * 119}\u{1F600}tail';
      final body =
          (SupportMessageBody.parse(text) as Ok<SupportMessageBody>).value;
      expect(body.preview, 'a' * 119);
    });
  });

  group('SupportConversationId', () {
    test('a UUID parses, lower-cased', () {
      final id = SupportConversationId.tryParse(
        'AAAAAAAA-0000-4000-8000-000000000001',
      );
      expect(
        (id as Ok<SupportConversationId>).value.value,
        'aaaaaaaa-0000-4000-8000-000000000001',
      );
    });

    test('anything else reads as a conversation that does not exist', () {
      for (final String? raw in <String?>[null, '', '1', "x' or '1'='1"]) {
        final id = SupportConversationId.tryParse(raw);
        expect(
          (id as Err<SupportConversationId>).error.code,
          'support.conversation_not_found',
        );
      }
    });
  });

  test('the status and the side parse from their tokens only', () {
    expect(
      (SupportConversationStatus.tryParse('archived')
              as Ok<SupportConversationStatus>)
          .value,
      SupportConversationStatus.archived,
    );
    expect(
      SupportConversationStatus.tryParse('deleted'),
      isA<Err<SupportConversationStatus>>(),
    );
    expect(
      (SupportSenderRole.tryParse('support') as Ok<SupportSenderRole>).value,
      SupportSenderRole.support,
    );
    expect(SupportSenderRole.tryParse('admin'), isA<Err<SupportSenderRole>>());
  });

  test('the two support push links', () {
    expect(PushLink.support, 'support');
    expect(PushLink.supportInbox, 'support_inbox');
  });
}
