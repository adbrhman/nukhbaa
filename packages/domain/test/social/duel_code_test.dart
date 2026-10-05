import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _valid = '9G7WZGEC2NVD';

void main() {
  group('DuelCode', () {
    test('parses the production shape', () {
      final result = DuelCode.tryParse(_valid);
      final code = (result as Ok<DuelCode>).value;
      expect(code.value, _valid);
      expect(DuelCode.codeLength, 12);
      expect(code.toString(), 'DuelCode($_valid)');
    });

    test('exposes the exact closed alphabet', () {
      expect(DuelCode.isAllowedChar('A'), isTrue);
      expect(DuelCode.isAllowedChar('9'), isTrue);
      for (final character in 'ILOU01ilou'.split('')) {
        expect(DuelCode.isAllowedChar(character), isFalse);
      }
    });

    test('rejects wrong length and unsupported characters', () {
      expect(
        (DuelCode.tryParse('ABC') as Err<DuelCode>).error.code,
        'social.duel_code_malformed',
      );
      expect(
        (DuelCode.tryParse('9G7WZGEC2NVD0') as Err<DuelCode>).error.code,
        'social.duel_code_malformed',
      );
    });

    test('rejects null and empty values', () {
      expect(
        (DuelCode.tryParse(null) as Err<DuelCode>).error.code,
        'social.duel_code_empty',
      );
      expect(
        (DuelCode.tryParse('') as Err<DuelCode>).error.code,
        'social.duel_code_empty',
      );
    });
  });
}
