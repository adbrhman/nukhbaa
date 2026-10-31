import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  group('H2hAbsenceViewDto', () {
    test('round-trips every part of the view', () {
      const view = H2hAbsenceViewDto(
        monthStart: '2026-11-01',
        active: true,
        nextRound: 4,
        relegatesAt: '2026-11-04T14:00:00.000Z',
        rounds: [
          H2hAbsenceRoundDto(
            roundId: 'r1',
            round: 1,
            day: '2026-11-01',
            locked: true,
            counted: false,
            absent: 0,
            excusedReason: 'تعطل',
          ),
        ],
        watch: [
          H2hAbsenceWatchDto(
            player: H2hAbsencePlayerDto(userId: 'u1', displayName: 'سالم'),
            group: 2,
            absentRounds: [2, 3],
            warned: true,
          ),
        ],
        candidates: [
          H2hAbsenceCandidateDto(
            player: H2hAbsencePlayerDto(userId: 'u5', displayName: null),
            group: 5,
            facts: H2hAbsenceFactsDto(
              missed: 2,
              points: 40,
              exact: 3,
              activeDays: 19,
            ),
          ),
        ],
        moves: [
          H2hSeatMoveDto(
            id: 'm1',
            kind: 'admin',
            fromRound: 4,
            out: H2hAbsencePlayerDto(userId: 'u1', displayName: 'سالم'),
            into: H2hAbsencePlayerDto(userId: 'u5', displayName: 'صالح'),
            eliteGroup: 2,
            extraGroup: 5,
            absentRounds: [1, 2, 3],
            createdAt: '2026-11-04T14:00:00.000Z',
            facts: H2hAbsenceFactsDto(
              missed: 2,
              points: 40,
              exact: 3,
              activeDays: 19,
            ),
            reason: 'تلاعب',
            decidedBy: H2hAbsencePlayerDto(userId: 'a1', displayName: 'مشرف'),
          ),
        ],
      );

      final back = H2hAbsenceViewDto.fromJson(view.toJson());

      expect(back.toJson(), view.toJson());
      expect(back.moves.single.into.displayName, 'صالح');
      expect(back.moves.single.decidedBy!.userId, 'a1');
      expect(back.watch.single.absentRounds, [2, 3]);
      expect(back.rounds.single.excusedReason, 'تعطل');
    });

    test('tolerates an empty body', () {
      final view = H2hAbsenceViewDto.fromJson(const {});

      expect(view.active, isFalse);
      expect(view.nextRound, isNull);
      expect(view.moves, isEmpty);
    });

    test('the requests carry their fields', () {
      expect(
        const H2hRelegationRequestDto(userId: 'u1', reason: 'r').toJson(),
        {'user_id': 'u1', 'reason': 'r'},
      );
      expect(const H2hExcusalRequestDto(roundId: 'r1', reason: 'r').toJson(), {
        'round_id': 'r1',
        'reason': 'r',
      });
    });
  });
}
