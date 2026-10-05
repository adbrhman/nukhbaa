import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _duelId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _challengeId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const _fixtureId = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
const _challenger = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
const _opponent = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';

Result<Duel> _createDuel({
  String challenger = _challenger,
  String opponent = _opponent,
  DateTime? acceptedAt,
}) => Duel.create(
  id: const DuelId(_duelId),
  challengeId: const DuelChallengeId(_challengeId),
  fixture: const FixtureRef(_fixtureId),
  challengerParticipantId: ParticipantId(challenger),
  opponentParticipantId: ParticipantId(opponent),
  acceptedAt: acceptedAt ?? DateTime.utc(2026, 10, 5, 12),
);

Duel _duel() => (_createDuel() as Ok<Duel>).value;

void main() {
  group('Duel.create', () {
    test('creates one accepted confrontation without derived score fields', () {
      final duel = _duel();
      expect(duel.id, const DuelId(_duelId));
      expect(duel.challengeId, const DuelChallengeId(_challengeId));
      expect(duel.fixture, const FixtureRef(_fixtureId));
      expect(duel.acceptedAt, DateTime.utc(2026, 10, 5, 12));
      expect(duel.createdAt, duel.acceptedAt);
    });

    test('rejects the same participant on both sides', () {
      final result = _createDuel(opponent: _challenger);
      expect(
        (result as Err<Duel>).error.code,
        'social.duel_participants_must_differ',
      );
    });

    test('requires UTC acceptance time', () {
      final result = _createDuel(acceptedAt: DateTime(2026, 10, 5, 12));
      expect(
        (result as Err<Duel>).error.code,
        'social.duel_accepted_at_not_utc',
      );
    });
  });

  group('Duel participants', () {
    test('identifies members and their opponents', () {
      final duel = _duel();
      const challenger = ParticipantId(_challenger);
      const opponent = ParticipantId(_opponent);
      const outsider = ParticipantId('ffffffff-ffff-ffff-ffff-ffffffffffff');

      expect(duel.containsParticipant(challenger), isTrue);
      expect(duel.containsParticipant(opponent), isTrue);
      expect(duel.containsParticipant(outsider), isFalse);
      expect(duel.opponentOf(challenger), opponent);
      expect(duel.opponentOf(opponent), challenger);
      expect(duel.opponentOf(outsider), isNull);
    });
  });
}
