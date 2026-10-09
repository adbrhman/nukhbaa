import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);

DateTime _day(int d) => DateTime.utc(2026, 11, d);

/// Kickoff [hour]:00 Riyadh on November [d], as UTC.
DateTime _kickoff(int d, int hour) => DateTime.utc(2026, 11, d, hour - 3);

H2hRound _round(int number, int day, {bool locked = false}) => H2hRound(
  id: H2hRoundId('00000000-0000-4000-8000-000000000${100 + number}'),
  monthStart: _november,
  number: number,
  day: _day(day),
  fixtureCount: 8,
  approvedBy: null,
  lockedAt: locked ? DateTime.utc(2026, 11, day, 12) : null,
);

ApproveH2hRound _approve(FakeH2hRoundStore rounds, DateTime now) =>
    ApproveH2hRound(
      rounds: rounds,
      idGenerator: SequenceIds(),
      clock: AtClock(now),
    );

void main() {
  group('ApproveH2hRound', () {
    final morning = DateTime.utc(2026, 11, 10, 6);

    test('only an admin approves', () async {
      final rounds = FakeH2hRoundStore()..dayOf(_day(10), 8, _kickoff(10, 18));
      final result = await _approve(
        rounds,
        morning,
      ).call(principal: player, day: _day(10));

      expect((result as Err<H2hRound>).error.kind, ErrorKind.authorization);
    });

    test('approves a day of six fixtures or more as the next round', () async {
      final rounds = FakeH2hRoundStore()
        ..addRound(_round(1, 8, locked: true))
        ..dayOf(_day(10), 8, _kickoff(10, 18));

      final result = await _approve(
        rounds,
        morning,
      ).call(principal: admin, day: _day(10));

      final round = (result as Ok<H2hRound>).value;
      expect(round.number, 2);
      expect(round.day, _day(10));
      expect(round.approvedBy, admin.userId);
      expect(rounds.byMonth[_november], hasLength(2));
    });

    test('an admin may approve a five-fixture fill day', () async {
      final rounds = FakeH2hRoundStore()..dayOf(_day(10), 5, _kickoff(10, 18));

      final result = await _approve(
        rounds,
        morning,
      ).call(principal: admin, day: _day(10));

      expect(result.isOk, isTrue);
    });

    test('refuses a day of four fixtures', () async {
      final rounds = FakeH2hRoundStore()..dayOf(_day(10), 4, _kickoff(10, 18));

      final result = await _approve(
        rounds,
        morning,
      ).call(principal: admin, day: _day(10));

      expect((result as Err<H2hRound>).error.code, 'h2h.round_not_eligible');
    });

    test('refuses a day that already kicked off', () async {
      final rounds = FakeH2hRoundStore()..dayOf(_day(10), 8, _kickoff(10, 8));

      final result = await _approve(
        rounds,
        morning,
      ).call(principal: admin, day: _day(10));

      expect((result as Err<H2hRound>).error.code, 'h2h.round_day_started');
    });

    test('refuses a day before the last round', () async {
      final rounds = FakeH2hRoundStore()
        ..addRound(_round(1, 12))
        ..dayOf(_day(10), 8, _kickoff(10, 18));

      final result = await _approve(
        rounds,
        morning,
      ).call(principal: admin, day: _day(10));

      expect((result as Err<H2hRound>).error.code, 'h2h.round_out_of_order');
    });

    test('refuses a twentieth round', () async {
      final rounds = FakeH2hRoundStore();
      for (var n = 1; n <= 19; n++) {
        rounds.addRound(_round(n, n, locked: true));
      }
      rounds.dayOf(_day(25), 12, _kickoff(25, 18));

      final result = await _approve(
        rounds,
        DateTime.utc(2026, 11, 25, 6),
      ).call(principal: admin, day: _day(25));

      expect((result as Err<H2hRound>).error.code, 'h2h.round_not_eligible');
    });
  });

  group('WithdrawH2hRound', () {
    test('passes an admin request to the store, refuses a player', () async {
      final rounds = FakeH2hRoundStore();
      final useCase = WithdrawH2hRound(rounds: rounds);
      const id = H2hRoundId('00000000-0000-4000-8000-000000000101');

      final refused = await useCase.call(principal: player, roundId: id);
      final done = await useCase.call(principal: admin, roundId: id);

      expect((refused as Err<void>).error.kind, ErrorKind.authorization);
      expect(done.isOk, isTrue);
      expect(rounds.withdrawCalls, [id]);
    });
  });

  group('RunH2hRounds', () {
    RunH2hRounds run(FakeH2hRoundStore rounds, FakeH2hLeagueStore leagues) =>
        RunH2hRounds(
          rounds: rounds,
          leagues: leagues,
          idGenerator: SequenceIds(),
        );

    test(
      'approves tomorrow when its first kickoff is within 24 hours',
      () async {
        final rounds = FakeH2hRoundStore()
          ..dayOf(_day(10), 2, _kickoff(10, 18))
          ..dayOf(_day(11), 9, _kickoff(11, 15));
        final now = DateTime.utc(2026, 11, 10, 16); // 19:00 Riyadh

        final result = await run(rounds, FakeH2hLeagueStore()).call(now: now);

        expect((result as Ok<H2hRoundsRun>).value.approved, 1);
        final approved = rounds.byMonth[_november]!.single;
        expect(approved.day, _day(11));
        expect(approved.approvedBy, isNull);
      },
    );

    test(
      'leaves a day more than 24 hours away, and a fill day, alone',
      () async {
        final rounds = FakeH2hRoundStore()
          ..dayOf(_day(10), 5, _kickoff(10, 22))
          ..dayOf(_day(11), 9, _kickoff(11, 23));
        final now = DateTime.utc(2026, 11, 10, 6); // 09:00 Riyadh

        final result = await run(rounds, FakeH2hLeagueStore()).call(now: now);

        expect((result as Ok<H2hRoundsRun>).value.approved, 0);
        expect(rounds.byMonth[_november], isNull);
      },
    );

    test(
      'before the league opens, only a drawn pilot month gets rounds',
      () async {
        final october = DateTime.utc(2026, 10);
        final day = DateTime.utc(2026, 10, 25);
        final rounds = FakeH2hRoundStore()
          ..dayOf(day, 8, DateTime.utc(2026, 10, 25, 15));
        final now = DateTime.utc(2026, 10, 25, 6);

        final none = await run(rounds, FakeH2hLeagueStore()).call(now: now);
        expect((none as Ok<H2hRoundsRun>).value.approved, 0);

        final pilot = FakeH2hLeagueStore()
          ..months[october] = H2hMonthInfo(
            monthStart: october,
            isPilot: true,
            seatedCount: 8,
          );
        final some = await run(rounds, pilot).call(now: now);
        expect((some as Ok<H2hRoundsRun>).value.approved, 1);
      },
    );

    test('locks a round whose first match kicked off, and a past round with '
        'no fixture left', () async {
      final rounds = FakeH2hRoundStore()
        ..addRound(_round(1, 8))
        ..addRound(_round(2, 10))
        ..addRound(_round(3, 12))
        ..dayOf(_day(10), 8, _kickoff(10, 15))
        ..dayOf(_day(12), 8, _kickoff(12, 15));
      final now = DateTime.utc(2026, 11, 10, 13); // 16:00 Riyadh

      final result = await run(rounds, FakeH2hLeagueStore()).call(now: now);

      expect((result as Ok<H2hRoundsRun>).value.locked, 2);
      expect(rounds.lockCalls.map((id) => id.value).toList(), [
        '00000000-0000-4000-8000-000000000101',
        '00000000-0000-4000-8000-000000000102',
      ]);
    });
  });

  group('ListH2hRounds', () {
    test('lists the rounds and the days that may come next', () async {
      final rounds = FakeH2hRoundStore()
        ..addRound(_round(1, 8, locked: true))
        ..dayOf(_day(7), 9, _kickoff(7, 18))
        ..dayOf(_day(10), 9, _kickoff(10, 8))
        ..dayOf(_day(11), 5, _kickoff(11, 18))
        ..dayOf(_day(12), 4, _kickoff(12, 18))
        ..dayOf(_day(14), 11, _kickoff(14, 18));
      final useCase = ListH2hRounds(
        rounds: rounds,
        leagues: FakeH2hLeagueStore(),
        clock: AtClock(DateTime.utc(2026, 11, 10, 9)),
      );

      final result = await useCase.call(principal: admin);

      final overview = (result as Ok<H2hRoundsOverview>).value;
      expect(overview.monthStart, _november);
      expect(overview.rounds, hasLength(1));
      expect(overview.candidates.map((c) => c.fixtures.day).toList(), [
        _day(11),
        _day(14),
      ]);
      expect(overview.candidates.map((c) => c.kind).toList(), [
        H2hRoundKind.fill,
        H2hRoundKind.regular,
      ]);
    });
  });
}
