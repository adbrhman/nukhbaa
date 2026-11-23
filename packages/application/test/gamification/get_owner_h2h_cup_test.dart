import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);

/// 2026-11-22 12:00 UTC: the 22nd in Riyadh.
final _now = DateTime.utc(2026, 11, 22, 12);

final class _Cups implements H2hCupStore {
  _Cups(this.state);

  final H2hCupState state;

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async =>
      Result.ok(monthStart == _november ? state : H2hCupState.empty);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

H2hCupEntry _entry(int user, int place, int group) => H2hCupEntry(
  userId: userNo(user),
  place: place,
  groupNumber: group,
  leaguePoints: 40,
  pointsFor: 100,
  exactCount: 10,
);

/// Users 1-4 are path 1 (groups 1-4); users 5-8 are path 2; 9-12 path 3.
List<H2hCupEntry> _entries() => [
  for (var g = 1; g <= 4; g++) _entry(g, 1, g),
  for (var g = 1; g <= 4; g++) _entry(4 + g, 2, g),
  for (var g = 1; g <= 4; g++) _entry(8 + g, 3, g),
];

H2hCupStage _semi(int place, int first) => H2hCupStage(
  id: H2hCupStageId('55555555-5555-4555-8555-55555555555$place'),
  monthStart: _november,
  step: H2hCupStep(place, H2hCupRound.semi),
  attempt: 1,
  day: DateTime.utc(2026, 11, 22),
  fixtureCount: 8,
  lockedAt: DateTime.utc(2026, 11, 22, 9),
  pairs: [
    H2hCupPair(slot: 1, home: userNo(first), away: userNo(first + 2)),
    H2hCupPair(slot: 2, home: userNo(first + 1), away: userNo(first + 3)),
  ],
  results: [
    H2hCupResult(
      slot: 1,
      winner: userNo(first),
      outcome: H2hCupOutcome.points.wire,
      home: const H2hCupSide(points: 9, exact: 1, predicted: 6),
      away: const H2hCupSide(points: 4, exact: 0, predicted: 6),
    ),
    H2hCupResult(
      slot: 2,
      winner: null,
      outcome: H2hCupOutcome.bothAbsent.wire,
      home: H2hCupSide.absent,
      away: H2hCupSide.absent,
    ),
  ],
);

GetOwnerH2hCup _useCase({FakeH2hRoundStore? rounds}) => GetOwnerH2hCup(
  cups: _Cups(
    H2hCupState(
      entries: _entries(),
      stages: [_semi(1, 1), _semi(2, 5)],
      titles: const <H2hCupTitle>[],
    ),
  ),
  rounds: rounds ?? FakeH2hRoundStore(),
  profiles: NamingProfiles(),
  clock: AtClock(_now),
);

void main() {
  group('GetOwnerH2hCup', () {
    test('the owner reads every path with names, stages and results', () async {
      final result = await _useCase()(principal: admin);

      final cup = (result as Ok<OwnerH2hCup>).value;
      expect(cup.monthStart, _november);
      expect(cup.months.map((m) => m.monthStart).toList(), [_november]);
      expect(cup.months.single.hasCup, isTrue);
      expect(cup.paths.map((p) => p.place).toList(), [1, 2, 3]);
      expect(cup.paths.map((p) => p.entrants.length).toList(), [4, 4, 4]);

      final one = cup.paths.first;
      expect(one.entrants.first.displayName, 'name ${userNo(1).value}');
      final semi = one.stages.first;
      expect(semi.phase, MyH2hCupPhase.decided);
      expect(semi.pairs, hasLength(2));
      expect(semi.pairs.first.result?.winner, userNo(1));
      expect(semi.pairs.last.result?.outcome, 'both_absent');
      expect(one.stages.last.phase, MyH2hCupPhase.waiting);

      // Path 3 has no stage yet: both are waiting.
      expect(cup.paths.last.stages.map((s) => s.phase).toList(), [
        MyH2hCupPhase.waiting,
        MyH2hCupPhase.waiting,
      ]);
    });

    test('the month\'s rounds are listed with their state', () async {
      final rounds = FakeH2hRoundStore()
        ..addRound(
          H2hRound(
            id: const H2hRoundId('00000000-0000-4000-8000-000000000401'),
            monthStart: _november,
            number: 1,
            day: DateTime.utc(2026, 11, 3),
            fixtureCount: 8,
            approvedBy: null,
            lockedAt: DateTime.utc(2026, 11, 3, 12),
          ),
        )
        ..addRound(
          H2hRound(
            id: const H2hRoundId('00000000-0000-4000-8000-000000000402'),
            monthStart: _november,
            number: 2,
            day: DateTime.utc(2026, 11, 4),
            fixtureCount: 7,
            approvedBy: userNo(50),
            lockedAt: null,
          ),
        );

      final result = await _useCase(rounds: rounds)(principal: admin);

      final list = (result as Ok<OwnerH2hCup>).value.rounds;
      expect(list.map((r) => r.number).toList(), [1, 2]);
      expect(list.first.locked, isTrue);
      expect(list.first.bySystem, isTrue);
      expect(list.last.locked, isFalse);
      expect(list.last.bySystem, isFalse);
    });

    test('a month with no cup has no paths', () async {
      final result = await _useCase()(
        principal: admin,
        month: DateTime.utc(2026, 12),
      );

      final cup = (result as Ok<OwnerH2hCup>).value;
      expect(cup.monthStart, DateTime.utc(2026, 12));
      expect(cup.paths, isEmpty);
    });

    test('a player is refused', () async {
      final result = await _useCase()(principal: player);

      expect(result, isA<Err<OwnerH2hCup>>());
    });
  });
}
