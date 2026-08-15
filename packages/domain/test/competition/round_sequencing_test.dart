import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _seasonId = '22222222-2222-2222-2222-222222222222';
const _otherSeasonId = '33333333-3333-3333-3333-333333333333';
const _round1Id = '44444444-4444-4444-4444-444444444444';
const _round2Id = '55555555-5555-5555-5555-555555555555';
const _round3Id = '66666666-6666-6666-6666-666666666666';

RulesetSnapshot _snapshot() =>
    (RulesetSnapshot.create(payload: const {'points': 5}, rulesetVersion: 1)
            as Ok<RulesetSnapshot>)
        .value;

Round _round({
  required String id,
  required int sequence,
  String seasonId = _seasonId,
  RoundStatus status = RoundStatus.open,
}) {
  final opened =
      (Round.open(
                id: RoundId(id),
                seasonId: SeasonId(seasonId),
                sequence: sequence,
                predictionDeadline: DateTime.utc(2026, 8, 1),
                ruleset: _snapshot(),
              )
              as Ok<Round>)
          .value;
  if (status == RoundStatus.open) return opened;
  if (status == RoundStatus.locked) {
    return (opened.transitionTo(RoundStatus.locked) as Ok<Round>).value;
  }
  final locked = (opened.transitionTo(RoundStatus.locked) as Ok<Round>).value;
  return (locked.transitionTo(RoundStatus.scored) as Ok<Round>).value;
}

void main() {
  group('isRoundPredictable', () {
    test('the first round in a season is predictable as soon as it opens', () {
      final round1 = _round(id: _round1Id, sequence: 1);
      expect(isRoundPredictable(round1, [round1]), isTrue);
    });

    test('a later round is NOT predictable while an earlier round is still '
        'open — the core bug this rule fixes (all rounds opened up front)', () {
      final round1 = _round(id: _round1Id, sequence: 1);
      final round2 = _round(id: _round2Id, sequence: 2);
      final seasonRounds = [round1, round2];

      expect(isRoundPredictable(round2, seasonRounds), isFalse);
    });

    test('a later round becomes predictable once every earlier round is '
        'locked', () {
      final round1 = _round(
        id: _round1Id,
        sequence: 1,
        status: RoundStatus.locked,
      );
      final round2 = _round(id: _round2Id, sequence: 2);
      final seasonRounds = [round1, round2];

      expect(isRoundPredictable(round2, seasonRounds), isTrue);
    });

    test('a later round is predictable once every earlier round is scored', () {
      final round1 = _round(
        id: _round1Id,
        sequence: 1,
        status: RoundStatus.scored,
      );
      final round2 = _round(id: _round2Id, sequence: 2);

      expect(isRoundPredictable(round2, [round1, round2]), isTrue);
    });

    test(
      'round 3 stays blocked if EITHER round 1 or round 2 is still open',
      () {
        final round1 = _round(
          id: _round1Id,
          sequence: 1,
          status: RoundStatus.locked,
        );
        final round2 = _round(id: _round2Id, sequence: 2); // still open
        final round3 = _round(id: _round3Id, sequence: 3);
        final seasonRounds = [round1, round2, round3];

        expect(isRoundPredictable(round3, seasonRounds), isFalse);
      },
    );

    test('a round that is itself locked or scored is never predictable, '
        'regardless of its siblings', () {
      final round1 = _round(
        id: _round1Id,
        sequence: 1,
        status: RoundStatus.locked,
      );
      expect(isRoundPredictable(round1, [round1]), isFalse);
    });

    test('later rounds in a DIFFERENT season never block this round', () {
      final round1 = _round(id: _round1Id, sequence: 1);
      final otherSeasonRoundBefore = _round(
        id: _round2Id,
        sequence: 1,
        seasonId: _otherSeasonId,
      );
      expect(
        isRoundPredictable(round1, [round1, otherSeasonRoundBefore]),
        isTrue,
      );
    });

    test('a missing earlier sibling (not present in seasonRounds) never '
        'blocks — the function trusts exactly what it is given', () {
      final round2 = _round(id: _round2Id, sequence: 2);
      expect(isRoundPredictable(round2, [round2]), isTrue);
    });
  });
}
