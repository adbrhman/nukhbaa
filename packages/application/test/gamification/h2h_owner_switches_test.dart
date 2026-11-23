/// The owners' switches of the head-to-head league (script 304, migration
/// 0225): `h2h_rounds` stops new rounds (the scheduler's and the admin's),
/// `h2h_cup` stops the cup's keeping, `h2h_cup_crowning` stops its titles.
/// A switch that cannot be read holds the work, as the month's crowning
/// does; with none wired nothing is held.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);

final class _Switches implements OwnerSwitches {
  _Switches({this.off = const <OwnerSwitch>{}, this.unreadable = false});

  final Set<OwnerSwitch> off;
  final bool unreadable;

  @override
  Future<Result<bool>> isOn(OwnerSwitch which) async => unreadable
      ? const Result.err(AppError.transient('test.down', 'down'))
      : Result.ok(!off.contains(which));
}

/// Nineteen November rounds, as a month that finished its league has.
FakeH2hRoundStore _novemberLeague() {
  final rounds = FakeH2hRoundStore();
  for (var n = 1; n <= 19; n++) {
    rounds.addRound(
      H2hRound(
        id: H2hRoundId('00000000-0000-4000-8000-000000000${500 + n}'),
        monthStart: _november,
        number: n,
        day: DateTime.utc(2026, 11, n),
        fixtureCount: 8,
        approvedBy: null,
        lockedAt: DateTime.utc(2026, 11, n, 12),
      ),
    );
  }
  return rounds;
}

FakeH2hLeagueStore _novemberDrawn() => FakeH2hLeagueStore()
  ..months[_november] = H2hMonthInfo(
    monthStart: _november,
    isPilot: false,
    seatedCount: 80,
  );

/// A cup that records its crownings and answers one stored state.
final class _Cups implements H2hCupStore {
  _Cups(this.state);

  final H2hCupState state;
  final List<int> crowned = <int>[];
  int reads = 0;

  @override
  Future<Result<H2hCupState>> stateOf(DateTime monthStart) async {
    reads++;
    return Result.ok(monthStart == _november ? state : H2hCupState.empty);
  }

  @override
  Future<Result<void>> crown({
    required DateTime monthStart,
    required int place,
    required UserId? champion,
    required UserId? runnerUp,
    required String how,
  }) async {
    crowned.add(place);
    return const Result.ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

H2hCupState _onePathOneEntrant() => H2hCupState(
  entries: [
    H2hCupEntry(
      userId: userNo(1),
      place: 1,
      groupNumber: 1,
      leaguePoints: 40,
      pointsFor: 100,
      exactCount: 10,
    ),
  ],
  stages: const <H2hCupStage>[],
  titles: const <H2hCupTitle>[],
);

RunH2hCup _cup(_Cups cups, OwnerSwitches? switches) => RunH2hCup(
  cups: cups,
  rounds: _novemberLeague(),
  leagues: _novemberDrawn(),
  sheets: FakeH2hSheetReader(),
  idGenerator: SequenceIds(),
  ownerSwitches: switches,
);

void main() {
  group('ownerSwitchHolds', () {
    test('no switches wired holds nothing', () async {
      expect(await ownerSwitchHolds(null, OwnerSwitch.h2hRounds), isFalse);
    });

    test('on serves, off holds, unreadable holds', () async {
      expect(await ownerSwitchHolds(_Switches(), OwnerSwitch.h2hCup), isFalse);
      expect(
        await ownerSwitchHolds(
          _Switches(off: {OwnerSwitch.h2hCup}),
          OwnerSwitch.h2hCup,
        ),
        isTrue,
      );
      expect(
        await ownerSwitchHolds(_Switches(unreadable: true), OwnerSwitch.h2hCup),
        isTrue,
      );
    });

    test('the three keys of migration 0225', () {
      expect(OwnerSwitch.byKey('h2h_rounds'), OwnerSwitch.h2hRounds);
      expect(OwnerSwitch.byKey('h2h_cup'), OwnerSwitch.h2hCup);
      expect(OwnerSwitch.byKey('h2h_cup_crowning'), OwnerSwitch.h2hCupCrowning);
    });
  });

  group('the rounds switch', () {
    // 01:00 Riyadh on 4 December: the 5th has eight fixtures, its first
    // kickoff within 24 hours.
    final now = DateTime.utc(2026, 12, 4, 22);
    final fifth = DateTime.utc(2026, 12, 5);

    FakeH2hRoundStore withADay() =>
        _novemberLeague()..dayOf(fifth, 8, DateTime.utc(2026, 12, 5, 15));

    Future<int> scheduled(OwnerSwitches? switches) async {
      final result = await RunH2hRounds(
        rounds: withADay(),
        leagues: _novemberDrawn(),
        idGenerator: SequenceIds(),
        ownerSwitches: switches,
      ).call(now: now);
      return (result as Ok<H2hRoundsRun>).value.approved;
    }

    test('on, the scheduler approves the day', () async {
      expect(await scheduled(_Switches()), 1);
    });

    test('off, the scheduler approves nothing', () async {
      expect(await scheduled(_Switches(off: {OwnerSwitch.h2hRounds})), 0);
    });

    test('unreadable, the scheduler approves nothing', () async {
      expect(await scheduled(_Switches(unreadable: true)), 0);
    });

    test('off, an admin\'s approval is refused', () async {
      final result = await ApproveH2hRound(
        rounds: withADay(),
        idGenerator: SequenceIds(),
        clock: AtClock(now),
        ownerSwitches: _Switches(off: {OwnerSwitch.h2hRounds}),
      ).call(principal: admin, day: fifth);

      expect((result as Err<H2hRound>).error.code, 'h2h.rounds_paused');
    });

    test('on, an admin\'s approval stands', () async {
      final result = await ApproveH2hRound(
        rounds: withADay(),
        idGenerator: SequenceIds(),
        clock: AtClock(now),
        ownerSwitches: _Switches(),
      ).call(principal: admin, day: fifth);

      expect(result, isA<Ok<H2hRound>>());
    });
  });

  group('the cup switches', () {
    // The 22nd of November: the month's cup is on.
    final now = DateTime.utc(2026, 11, 22, 12);

    test('the cup off: nothing is read, nothing is kept', () async {
      final cups = _Cups(_onePathOneEntrant());

      final result = await _cup(
        cups,
        _Switches(off: {OwnerSwitch.h2hCup}),
      ).call(now: now);

      final run = (result as Ok<H2hCupRun>).value;
      expect(run.crowned, 0);
      expect(run.scheduled, 0);
      expect(cups.reads, 0);
      expect(cups.crowned, isEmpty);
    });

    test(
      'on, a lone qualifier is crowned and the empty paths are vacant',
      () async {
        final cups = _Cups(_onePathOneEntrant());

        final result = await _cup(cups, _Switches()).call(now: now);

        expect((result as Ok<H2hCupRun>).value.crowned, 3);
        expect(cups.crowned, [1, 2, 3]);
      },
    );

    test('the crowning off: the cup runs but crowns nobody', () async {
      final cups = _Cups(_onePathOneEntrant());

      final result = await _cup(
        cups,
        _Switches(off: {OwnerSwitch.h2hCupCrowning}),
      ).call(now: now);

      expect((result as Ok<H2hCupRun>).value.crowned, 0);
      expect(cups.reads, greaterThan(0));
      expect(cups.crowned, isEmpty);
    });

    test('the crowning unreadable: nobody is crowned', () async {
      final cups = _Cups(_onePathOneEntrant());

      await _cup(cups, _Switches(unreadable: true)).call(now: now);

      expect(cups.crowned, isEmpty);
    });
  });
}
