import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _uuid = '11111111-2222-3333-4444-555555555555';

void main() {
  group('DuelId.tryParse', () {
    test('accepts a canonical UUID', () {
      final result = DuelId.tryParse(_uuid);
      expect((result as Ok<DuelId>).value.value, _uuid);
    });

    test('rejects null, empty and malformed values', () {
      expect(
        (DuelId.tryParse(null) as Err<DuelId>).error.code,
        'social.duel_id_empty',
      );
      expect(
        (DuelId.tryParse('') as Err<DuelId>).error.code,
        'social.duel_id_empty',
      );
      expect(
        (DuelId.tryParse('not-a-uuid') as Err<DuelId>).error.code,
        'social.duel_id_malformed',
      );
    });

    test('remains distinct from the challenge id type', () {
      expect(const DuelId(_uuid), isNot(const DuelChallengeId(_uuid)));
    });
  });
}
