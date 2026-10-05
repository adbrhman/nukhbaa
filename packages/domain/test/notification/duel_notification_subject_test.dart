import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _challenge = '11111111-1111-4111-8111-111111111111';
const _actor = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';

void main() {
  test('a private challenge is told once per challenge', () {
    final subject = NotificationSubject.duelChallenged(
      challengeId: const DuelChallengeId(_challenge),
      actorUserId: const UserId(_actor),
    );
    expect(subject.kind, NotificationKind.duelChallenged);
    expect(subject.duelChallengeId, const DuelChallengeId(_challenge));
    expect(subject.actorUserId, const UserId(_actor));
    expect(subject.dedupeRef, 'duel_challenged:$_challenge');
  });

  test('each acceptance of a challenge is its own event', () {
    final first = NotificationSubject.duelAccepted(
      challengeId: const DuelChallengeId(_challenge),
      actorUserId: const UserId(_actor),
    );
    final second = NotificationSubject.duelAccepted(
      challengeId: const DuelChallengeId(_challenge),
      actorUserId: const UserId(_other),
    );
    expect(first.dedupeRef, 'duel_accepted:$_challenge:$_actor');
    expect(first.dedupeRef == second.dedupeRef, isFalse);
    expect(first == second, isFalse);
  });

  test('the duel kinds carry stable wire tokens', () {
    expect(NotificationKind.duelChallenged.wireValue, 'duel_challenged');
    expect(NotificationKind.duelAccepted.wireValue, 'duel_accepted');
    expect(
      (NotificationKind.tryParse('duel_accepted') as Ok<NotificationKind>)
          .value,
      NotificationKind.duelAccepted,
    );
  });

  test('a challenge push link carries its code', () {
    expect(PushLink.duel, 'duel');
    expect(PushLink.duelChallenge('ABCDEFGHJKMN'), 'duel:ABCDEFGHJKMN');
  });
}
