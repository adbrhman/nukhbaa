import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _uuid = '11111111-2222-3333-4444-555555555555';

void main() {
  group('DuelChallengeId.tryParse', () {
    test('accepts a canonical UUID', () {
      final result = DuelChallengeId.tryParse(_uuid);
      expect((result as Ok<DuelChallengeId>).value.value, _uuid);
    });

    test('rejects null, empty and malformed values', () {
      expect(
        (DuelChallengeId.tryParse(null) as Err<DuelChallengeId>).error.code,
        'social.duel_challenge_id_empty',
      );
      expect(
        (DuelChallengeId.tryParse('') as Err<DuelChallengeId>).error.code,
        'social.duel_challenge_id_empty',
      );
      expect(
        (DuelChallengeId.tryParse('not-a-uuid') as Err<DuelChallengeId>)
            .error
            .code,
        'social.duel_challenge_id_malformed',
      );
    });

    test('remains distinct from another EntityId type', () {
      expect(const DuelChallengeId(_uuid), isNot(const UserId(_uuid)));
    });
  });
}
