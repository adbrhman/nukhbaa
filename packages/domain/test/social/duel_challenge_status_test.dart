import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('DuelChallengeStatus', () {
    test('wireValue round-trips every stored state', () {
      for (final status in DuelChallengeStatus.values) {
        expect(
          (DuelChallengeStatus.tryParse(status.wireValue)
                  as Ok<DuelChallengeStatus>)
              .value,
          status,
        );
      }
    });

    test('only open is open', () {
      expect(DuelChallengeStatus.open.isOpen, isTrue);
      expect(DuelChallengeStatus.cancelled.isOpen, isFalse);
      expect(DuelChallengeStatus.declined.isOpen, isFalse);
    });

    test('unknown token is a validation error', () {
      final result = DuelChallengeStatus.tryParse('expired');
      expect(
        (result as Err<DuelChallengeStatus>).error.code,
        'social.duel_challenge_status_unknown',
      );
    });
  });
}
