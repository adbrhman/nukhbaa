import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// The group chat's pure rules (migration 0216, script 281).
void main() {
  group('H2hChatBody', () {
    test('keeps the text, trimmed', () {
      final result = H2hChatBody.parse('  أهلًا بالمجموعة  ');
      expect((result as Ok<H2hChatBody>).value.value, 'أهلًا بالمجموعة');
    });

    test('refuses nothing, and spaces only', () {
      for (final String? raw in <String?>[null, '', '   \n ']) {
        final result = H2hChatBody.parse(raw);
        expect(result, isA<Err<H2hChatBody>>());
        expect(
          (result as Err<H2hChatBody>).error.code,
          'h2h.chat_empty_message',
        );
      }
    });

    test('500 characters pass, 501 do not', () {
      expect(
        H2hChatBody.parse('x' * H2hChatBody.maxLength),
        isA<Ok<H2hChatBody>>(),
      );
      final result = H2hChatBody.parse('x' * (H2hChatBody.maxLength + 1));
      expect(
        (result as Err<H2hChatBody>).error.code,
        'h2h.chat_message_too_long',
      );
    });
  });
}
