import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _challengeId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _seasonId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _fixtureId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _participantId = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _targetId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

DuelCode _code([String value = '9G7WZGEC2NVD']) =>
    (DuelCode.tryParse(value) as Ok<DuelCode>).value;

DuelChallenge _challenge({
  UserId? target,
  int capacity = DuelChallenge.defaultCapacity,
  DateTime? createdAt,
}) =>
    (DuelChallenge.create(
              id: const DuelChallengeId(_challengeId),
              code: _code(),
              seasonId: const SeasonId(_seasonId),
              fixture: const FixtureRef(_fixtureId),
              challengerParticipantId: const ParticipantId(_participantId),
              targetUserId: target,
              capacity: capacity,
              createdAt: createdAt ?? DateTime.utc(2026, 10, 5, 12),
            )
            as Ok<DuelChallenge>)
        .value;

void main() {
  group('DuelChallenge.create', () {
    test('creates an open challenge with the default capacity', () {
      final challenge = _challenge();
      expect(challenge.capacity, 5);
      expect(challenge.status, DuelChallengeStatus.open);
      expect(challenge.isOpen, isTrue);
      expect(challenge.isPrivate, isFalse);
      expect(challenge.updatedAt, challenge.createdAt);
    });

    test('private challenge is fixed to capacity one', () {
      final challenge = _challenge(
        target: const UserId(_targetId),
        capacity: 1,
      );
      expect(challenge.isPrivate, isTrue);
      expect(challenge.targetUserId, const UserId(_targetId));
      expect(challenge.capacity, 1);
    });

    test('rejects capacity outside one through ten', () {
      expect(
        (DuelChallenge.create(
                  id: const DuelChallengeId(_challengeId),
                  code: _code(),
                  seasonId: const SeasonId(_seasonId),
                  fixture: const FixtureRef(_fixtureId),
                  challengerParticipantId: const ParticipantId(_participantId),
                  targetUserId: null,
                  capacity: 11,
                  createdAt: DateTime.utc(2026, 10, 5, 12),
                )
                as Err<DuelChallenge>)
            .error
            .code,
        'social.duel_challenge_capacity_out_of_range',
      );
    });

    test('rejects private capacity greater than one', () {
      final result = DuelChallenge.create(
        id: const DuelChallengeId(_challengeId),
        code: _code(),
        seasonId: const SeasonId(_seasonId),
        fixture: const FixtureRef(_fixtureId),
        challengerParticipantId: const ParticipantId(_participantId),
        targetUserId: const UserId(_targetId),
        capacity: 2,
        createdAt: DateTime.utc(2026, 10, 5, 12),
      );
      expect(
        (result as Err<DuelChallenge>).error.code,
        'social.duel_challenge_private_capacity_invalid',
      );
    });

    test('rejects non-UTC creation time', () {
      final result = DuelChallenge.create(
        id: const DuelChallengeId(_challengeId),
        code: _code(),
        seasonId: const SeasonId(_seasonId),
        fixture: const FixtureRef(_fixtureId),
        challengerParticipantId: const ParticipantId(_participantId),
        targetUserId: null,
        createdAt: DateTime(2026, 10, 5, 12),
      );
      expect(
        (result as Err<DuelChallenge>).error.code,
        'social.duel_challenge_created_at_not_utc',
      );
    });
  });

  group('DuelChallenge lifecycle', () {
    test('cancel moves open to cancelled and refreshes updatedAt', () {
      final challenge = _challenge();
      final cancelled =
          (challenge.cancel(at: DateTime.utc(2026, 10, 5, 12, 1))
                  as Ok<DuelChallenge>)
              .value;
      expect(cancelled.status, DuelChallengeStatus.cancelled);
      expect(cancelled.isOpen, isFalse);
      expect(cancelled.updatedAt, DateTime.utc(2026, 10, 5, 12, 1));
    });

    test('private challenge can be declined', () {
      final challenge = _challenge(
        target: const UserId(_targetId),
        capacity: 1,
      );
      final declined =
          (challenge.decline(at: DateTime.utc(2026, 10, 5, 12, 2))
                  as Ok<DuelChallenge>)
              .value;
      expect(declined.status, DuelChallengeStatus.declined);
    });

    test('public challenge cannot be declined', () {
      final result = _challenge().decline(at: DateTime.utc(2026, 10, 5, 12, 2));
      expect(
        (result as Err<DuelChallenge>).error.code,
        'social.duel_challenge_decline_requires_target',
      );
    });

    test('closed challenge cannot change state again', () {
      final challenge = _challenge();
      final cancelled =
          (challenge.cancel(at: DateTime.utc(2026, 10, 5, 12, 1))
                  as Ok<DuelChallenge>)
              .value;
      final result = cancelled.cancel(at: DateTime.utc(2026, 10, 5, 12, 2));
      expect(
        (result as Err<DuelChallenge>).error.code,
        'social.duel_challenge_not_open',
      );
    });

    test('lifecycle time must be UTC', () {
      final result = _challenge().cancel(at: DateTime(2026, 10, 5, 12, 1));
      expect(
        (result as Err<DuelChallenge>).error.code,
        'social.duel_challenge_updated_at_not_utc',
      );
    });
  });

  group('DuelChallenge.hasCapacity', () {
    test('tracks the accepted duel count without changing the aggregate', () {
      final challenge = _challenge(capacity: 2);
      expect(challenge.hasCapacity(0), isTrue);
      expect(challenge.hasCapacity(1), isTrue);
      expect(challenge.hasCapacity(2), isFalse);
      expect(challenge.hasCapacity(-1), isFalse);
      expect(challenge.capacity, 2);
    });
  });
}
