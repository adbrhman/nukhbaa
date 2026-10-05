import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fake_competition_repository.dart';
import '../competition/fakes.dart';
import 'duel_application_fakes.dart';

const _user = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _other = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _season = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _challenge = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _fixture = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _participant = 'ffffffff-ffff-ffff-ffff-ffffffffffff';
final _now = DateTime.utc(2026, 10, 5, 12);

DuelChallenge _challengeRow({UserId? target}) =>
    (DuelChallenge.create(
              id: const DuelChallengeId(_challenge),
              code: (DuelCode.tryParse('ABCDEFGHJKMN') as Ok<DuelCode>).value,
              seasonId: const SeasonId(_season),
              fixture: const FixtureRef(_fixture),
              challengerParticipantId: const ParticipantId(_participant),
              targetUserId: target,
              capacity: target == null ? DuelChallenge.defaultCapacity : 1,
              createdAt: _now,
            )
            as Ok<DuelChallenge>)
        .value;

void main() {
  test('only the challenger can cancel', () async {
    final duels = FakeDuelChallengeRepository()..seedChallenge(_challengeRow());
    final competition = FakeCompetitionRepository();
    final result = await CancelDuelChallenge(
      duels: duels,
      competition: competition,
    ).call(principal: userPrincipal(_other), challengeId: _challenge);
    expect((result as Err<void>).error.code, 'social.duel_not_challenger');
  });

  test('the invited target can decline a private challenge', () async {
    final duels = FakeDuelChallengeRepository()
      ..seedChallenge(_challengeRow(target: const UserId(_user)));
    final result = await DeclineDuelChallenge(
      duels: duels,
    ).call(principal: userPrincipal(_user), challengeId: _challenge);
    expect(result, isA<Ok<void>>());
  });
}
