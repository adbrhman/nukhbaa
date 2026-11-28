/// NK352C: the December absence plan on the month's own numbering. From
/// the draw of eight groups (NK353_01) the elite groups are 1 to 8, so a
/// player of group 7 goes down to the first extra group (9), the extra
/// groups follow (9 to 10), and without the month's count the old
/// four-group numbering still holds.
library;

import 'package:domain/domain.dart';
import 'package:test/test.dart';

UserId _u(int n) => UserId('u$n');

H2hLeagueId _lg(int n) =>
    H2hLeagueId('11111111-1111-4111-8111-${n.toString().padLeft(12, '0')}');

final _december = DateTime.utc(2026, 12);

H2hHeldSeat _seat(int user, H2hLeagueId league, int index, int slot) =>
    H2hHeldSeat(
      userId: _u(user),
      leagueId: league,
      groupIndex: index,
      slot: slot,
    );

H2hCountedRound _round(int n, Set<int> present) => H2hCountedRound(
  roundId: H2hRoundId(
    '22222222-2222-4222-8222-${n.toString().padLeft(12, '0')}',
  ),
  monthStart: _december,
  number: n,
  day: DateTime.utc(2026, 12, n),
  present: {for (final p in present) _u(p)},
);

H2hCandidateFacts _facts(int user, {int predicted = 10}) => H2hCandidateFacts(
  userId: _u(user),
  missed: 0,
  points: 0,
  exact: 0,
  activeDays: 20,
  predicted: predicted,
  outcomes: 0,
);

void main() {
  // Group 7 (elite of the eight): 70, 71. Group 9 (first extra): 90, 91.
  // Group 10 (the last that plays): 100, 101. 70 missed three rounds.
  final groups = [
    H2hAbsenceGroup(
      leagueId: _lg(7),
      number: 7,
      seats: [_seat(70, _lg(7), 6, 0), _seat(71, _lg(7), 6, 1)],
    ),
    H2hAbsenceGroup(
      leagueId: _lg(9),
      number: 9,
      seats: [_seat(90, _lg(9), 0, 0), _seat(91, _lg(9), 0, 1)],
    ),
    H2hAbsenceGroup(
      leagueId: _lg(10),
      number: 10,
      seats: [_seat(100, _lg(10), 1, 0), _seat(101, _lg(10), 1, 1)],
    ),
  ];
  final everyone = {70, 71, 90, 91, 100, 101};
  final counted = [
    for (var n = 1; n <= 3; n++) _round(n, everyone.difference({70})),
  ];
  final facts = [
    _facts(90),
    _facts(91, predicted: 30),
    _facts(100),
    _facts(101, predicted: 30),
  ];

  H2hDecemberPlan plan({int? eliteGroupCount}) {
    bool noRepeat(UserId _, H2hHeldSeat _) => false;
    return eliteGroupCount == null
        ? H2hAbsencePolicy.planDecemberMoves(
            groups: groups,
            waiting: const <H2hHeldSeat>[],
            open: const <H2hOpenVacancy>[],
            counted: counted,
            facts: facts,
            monthStart: _december,
            alreadyOut: const <UserId>{},
            alreadyIn: const <UserId>{},
            wouldRepeat: noRepeat,
          )
        : H2hAbsencePolicy.planDecemberMoves(
            groups: groups,
            waiting: const <H2hHeldSeat>[],
            open: const <H2hOpenVacancy>[],
            counted: counted,
            facts: facts,
            monthStart: _december,
            alreadyOut: const <UserId>{},
            alreadyIn: const <UserId>{},
            wouldRepeat: noRepeat,
            eliteGroupCount: eliteGroupCount,
          );
  }

  group('planDecemberMoves with the eight groups', () {
    test('an elite group of the eight goes down to the first extra', () {
      final p = plan(eliteGroupCount: 8);

      expect(p.vacancies, isEmpty);
      expect(p.unfilled, isEmpty);
      expect(p.moves, hasLength(1));
      expect(p.moves.single.out, _u(70));
      expect(p.moves.single.extraSeat.leagueId, _lg(9));
      expect(p.moves.single.substitute, _u(91));
    });

    test('without the count group 7 is an extra group: no group 8 plays, '
        'so he leaves his seat', () {
      final p = plan();

      expect(p.moves, isEmpty);
      expect(p.vacancies.single.out, _u(70));
    });
  });
}
