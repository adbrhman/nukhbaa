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

  group('SupportImage (0188)', () {
    final List<int> jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10];
    final List<int> png = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0,
    ];
    final List<int> webp = <int>[
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, //
    ];

    test('JPEG, PNG and WEBP whose signature matches their type pass', () {
      expect(SupportImage.parse(jpeg, 'image/jpeg'), isA<Ok<SupportImage>>());
      expect(
        SupportImage.parse(png, 'IMAGE/PNG; q=1'),
        isA<Ok<SupportImage>>(),
      );
      expect(SupportImage.parse(webp, 'image/webp'), isA<Ok<SupportImage>>());
    });

    test('a file that claims to be a picture and is not is refused', () {
      for (final (List<int>, String?) bad in <(List<int>, String?)>[
        (png, 'image/jpeg'),
        (<int>[0x25, 0x50, 0x44, 0x46], 'image/png'),
        (jpeg, 'image/gif'),
        (jpeg, null),
      ]) {
        final image = SupportImage.parse(bad.$1, bad.$2);
        expect(
          (image as Err<SupportImage>).error.code,
          'support.image_unsupported',
        );
      }
    });

    test('empty, or over 512 KB, is refused', () {
      expect(
        (SupportImage.parse(const <int>[], 'image/jpeg') as Err<SupportImage>)
            .error
            .code,
        'support.image_empty',
      );
      final List<int> big = <int>[...jpeg, ...List<int>.filled(512 * 1024, 0)];
      expect(
        (SupportImage.parse(big, 'image/jpeg') as Err<SupportImage>).error.code,
        'support.image_too_large',
      );
    });
  });
}
