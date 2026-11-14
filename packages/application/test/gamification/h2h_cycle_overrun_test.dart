/// The league plays its 19 rounds past the month's end, through the real
/// use-cases (NK279, decided by the owner on 2026-11-14, December 2026 on):
/// December with 17 rounds by its last day takes 2 and 3 January as its
/// rounds 18 and 19, locks them, is not judged before its 19th round and is
/// judged after it; January is not drawn meanwhile; the player reads
/// December; `NUKHBA_H2H_CYCLE_OVERRUN=off` gives every day to its own
/// month again; and November keeps its month's end.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
final _december = DateTime.utc(2026, 12);
final _january = DateTime.utc(2027);

H2hLeagueId _group(int n) =>
    H2hLeagueId('11111111-1111-4111-8279-${n.toString().padLeft(12, '0')}');

H2hRoundId _rid(DateTime month, int n) => H2hRoundId(
  '22222222-2222-4222-8279-${month.month.toString().padLeft(4, '0')}'
  '${n.toString().padLeft(8, '0')}',
);

H2hMember _member(int user, int slot) => H2hMember(
  userId: userNo(user),
  slot: slot,
  joinedAt: DateTime.utc(2026, 12),
);

/// A drawn month of three groups of four: the elite group (players 0..3),
/// group 5 (10..13) and group 6 (20..23), each with [rounds] rounds from
/// [firstDay] on, one a day, all locked and settled.
final class _World {
  _World(this.month, {required int rounds, required DateTime firstDay}) {
    leagues.months[month] = H2hMonthInfo(
      monthStart: month,
      isPilot: false,
      seatedCount: 12,
    );
    leagues.drawn[month] = [
      for (final (g, division, index) in [
        (1, H2hDivision.first, 0),
        (5, H2hDivision.second, 0),
        (6, H2hDivision.second, 1),
      ])
        H2hDrawnGroup(
          leagueId: _group(g),
          group: H2hDrawGroup(
            division: division,
            groupIndex: index,
            seats: const <H2hDrawSeat>[],
          ),
        ),
    ];
    for (var n = 1; n <= rounds; n++) {
      addRound(n, firstDay.add(Duration(days: n - 1)));
    }
    for (final (g, first) in [(1, 0), (5, 10), (6, 20)]) {
      sheets.sheets[_group(g)] = H2hGroupSheet(
        members: [for (var s = 0; s < 4; s++) _member(first + s, s)],
        scores: [
          for (var n = 1; n <= 19; n++)
            for (var s = 0; s < 4; s++)
              H2hRoundScore(
                userId: userNo(first + s),
                round: n,
                points: 10 - s,
                exactCount: 0,
                predictedCount: 6,
              ),
        ],
        settledRounds: {for (var n = 1; n <= 19; n++) n},
        voidRounds: const <int>{},
      );
      for (var s = 0; s < 4; s++) {
        sheets.activeDays[userNo(first + s)] = 20;
      }
    }
    leagues.seat(
      userNo(0),
      H2hSeat(
        leagueId: _group(1),
        monthStart: month,
        division: H2hDivision.first,
        groupIndex: 0,
        slot: 0,
        capacity: H2hLeaguePolicy.groupCapacity,
        divisionGroups: 1,
        isPilot: false,
        joinedAt: month,
      ),
    );
  }

  final DateTime month;
  final FakeH2hLeagueStore leagues = FakeH2hLeagueStore();
  final FakeH2hRoundStore rounds = FakeH2hRoundStore();
  final FakeH2hSheetReader sheets = FakeH2hSheetReader();
  final RecordingEvents events = RecordingEvents();

  /// Adds round [n] of [month] on [day], locked.
  void addRound(int n, DateTime day, {bool locked = true}) {
    rounds.addRound(
      H2hRound(
        id: _rid(month, n),
        monthStart: month,
        number: n,
        day: day,
        fixtureCount: 8,
        approvedBy: null,
        lockedAt: locked ? day.add(const Duration(hours: 12)) : null,
      ),
    );
  }

  RunH2hRounds roundsJob({bool overrun = true}) => RunH2hRounds(
    rounds: rounds,
    leagues: leagues,
    idGenerator: SequenceIds(),
    cycleOverrun: overrun,
  );

  CloseH2hMonth closeJob({bool overrun = true}) => CloseH2hMonth(
    leagues: leagues,
    rounds: rounds,
    sheets: sheets,
    events: events,
    idGenerator: SequenceIds(),
    cycleOverrun: overrun,
  );

  Future<MyH2hLeague> read(DateTime now) async =>
      ((await GetMyH2hLeague(
                leagues: leagues,
                rounds: rounds,
                sheets: sheets,
                profiles: NamingProfiles(),
                clock: AtClock(now),
              )(
                principal: AuthenticatedUser(
                  userId: userNo(0),
                  role: PlatformRole.user,
                ),
              ))
              as Ok<MyH2hLeague>)
          .value;
}

/// December started late: rounds 1..17 on 13..29 December.
_World _lateDecember() =>
    _World(_december, rounds: 17, firstDay: DateTime.utc(2026, 12, 13));

void main() {
  group('the cycle a day belongs to', () {
    test('a day of January belongs to December while it has fewer than '
        '19 rounds, to January once it has them or is judged', () async {
      final w = _lateDecember();
      Future<DateTime> cycle(DateTime day) async =>
          ((await h2hCycleOf(leagues: w.leagues, rounds: w.rounds, day: day))
                  as Ok<DateTime>)
              .value;

      expect(await cycle(DateTime.utc(2027, 1, 2)), _december);
      expect(await cycle(DateTime.utc(2026, 12, 30)), _december);

      w.addRound(18, DateTime.utc(2027, 1, 2));
      w.addRound(19, DateTime.utc(2027, 1, 3));
      expect(await cycle(DateTime.utc(2027, 1, 4)), _january);

      final judged = _lateDecember();
      judged.leagues.closed[_december] = 12;
      expect(
        ((await h2hCycleOf(
                  leagues: judged.leagues,
                  rounds: judged.rounds,
                  day: DateTime.utc(2027, 1, 2),
                ))
                as Ok<DateTime>)
            .value,
        _january,
      );
    });

    test('November keeps its month: 1 December is December\'s', () async {
      final w = _World(
        _november,
        rounds: 12,
        firstDay: DateTime.utc(2026, 11, 10),
      );
      expect(
        ((await h2hCycleOf(
                  leagues: w.leagues,
                  rounds: w.rounds,
                  day: DateTime.utc(2026, 12, 1),
                ))
                as Ok<DateTime>)
            .value,
        _december,
      );
    });
  });

  group('RunH2hRounds', () {
    // 01:00 Riyadh on 2 January: eight fixtures, the first at 18:00.
    final now = DateTime.utc(2027, 1, 1, 22);
    final second = DateTime.utc(2027, 1, 2);

    test(
      '2 January becomes December\'s round 18, not January\'s first',
      () async {
        final w = _lateDecember();
        w.rounds.dayOf(second, 8, DateTime.utc(2027, 1, 2, 15));

        final run = await w.roundsJob()(now: now);

        expect((run as Ok<H2hRoundsRun>).value.approved, 1);
        final december = w.rounds.byMonth[_december]!;
        expect(december, hasLength(18));
        expect(december.last.number, 18);
        expect(december.last.day, second);
        expect(w.rounds.byMonth[_january], isNull);
      },
    );

    test('December\'s round past its end is locked at its kickoff', () async {
      final w = _lateDecember();
      w.rounds.dayOf(second, 8, DateTime.utc(2027, 1, 2, 15));
      w.addRound(18, second, locked: false);

      await w.roundsJob()(now: DateTime.utc(2027, 1, 2, 15, 30));

      expect(w.rounds.lockCalls, contains(_rid(_december, 18)));
    });

    test('with NUKHBA_H2H_CYCLE_OVERRUN=off the day is January\'s', () async {
      final w = _lateDecember();
      w.rounds.dayOf(second, 8, DateTime.utc(2027, 1, 2, 15));

      await w.roundsJob(overrun: false)(now: now);

      expect(w.rounds.byMonth[_december], hasLength(17));
      expect(w.rounds.byMonth[_january]!.single.number, 1);
    });
  });

  group('CloseH2hMonth and the next draw', () {
    test('December is not judged with 18 rounds, even days after its end; '
        'January is not drawn meanwhile', () async {
      final w = _lateDecember()..addRound(18, DateTime.utc(2027, 1, 2));

      final closed = await w.closeJob()(now: DateTime.utc(2027, 1, 5));

      expect((closed as Ok<int>).value, 0);
      expect(w.leagues.closed.containsKey(_december), isFalse);
      expect(w.events.recorded, isEmpty);

      final drawn = await DrawH2hMonth(
        leagues: w.leagues,
        source: FakeH2hDrawSource(),
        idGenerator: SequenceIds(),
      )(now: DateTime.utc(2027, 1, 5));
      expect((drawn as Ok<int>).value, 0);
      expect(w.leagues.months.containsKey(_january), isFalse);
    });

    test('after its 19th round on 3 January, December is judged three '
        'hours after that day ends, not before', () async {
      final w = _lateDecember()
        ..addRound(18, DateTime.utc(2027, 1, 2))
        ..addRound(19, DateTime.utc(2027, 1, 3));

      // 3 January ends at 21:00 UTC; the grace is three hours.
      final early = await w.closeJob()(now: DateTime.utc(2027, 1, 3, 23));
      expect((early as Ok<int>).value, 0);

      final late = await w.closeJob()(now: DateTime.utc(2027, 1, 4, 0, 30));
      expect((late as Ok<int>).value, 1);
      expect(w.leagues.closed.containsKey(_december), isTrue);
      expect(w.events.recorded, hasLength(12));
    });

    test('with NUKHBA_H2H_CYCLE_OVERRUN=off December is judged at its end '
        'with the rounds it has', () async {
      final w = _lateDecember();

      final closed = await w.closeJob(overrun: false)(
        now: DateTime.utc(2027, 1, 1, 0, 30),
      );

      expect((closed as Ok<int>).value, 1);
    });

    test('a December that finished its 19 rounds inside the month is judged '
        'at the month\'s end, as before', () async {
      final w = _World(
        _december,
        rounds: 19,
        firstDay: DateTime.utc(2026, 12, 2),
      );

      final early = await w.closeJob()(now: DateTime.utc(2026, 12, 31, 12));
      expect((early as Ok<int>).value, 0);
      final late = await w.closeJob()(now: DateTime.utc(2027, 1, 1, 0, 30));
      expect((late as Ok<int>).value, 1);
    });
  });

  group('GetMyH2hLeague', () {
    test('on 2 January the player reads December, still playing', () async {
      final w = _lateDecember()..addRound(18, DateTime.utc(2027, 1, 2));

      final league = await w.read(DateTime.utc(2027, 1, 2, 9));

      expect(league.state, H2hLeagueState.open);
      expect(league.monthStart, _december);
      expect(league.rounds, hasLength(18));
    });

    test('once December has its 19 rounds the player reads January', () async {
      final w = _lateDecember()
        ..addRound(18, DateTime.utc(2027, 1, 2))
        ..addRound(19, DateTime.utc(2027, 1, 3));

      final league = await w.read(DateTime.utc(2027, 1, 5, 9));

      expect(league.monthStart, _january);
      expect(league.state, H2hLeagueState.drawPending);
    });
  });

  group('H2hLeaguePolicy', () {
    test('cycleOf: only a drawn, unjudged December-rules month before the '
        'day\'s own with fewer than 19 rounds takes the day', () {
      final day = DateTime.utc(2027, 1, 2);
      DateTime of({
        bool drawn = true,
        int rounds = 17,
        bool judged = false,
        DateTime? on,
      }) => H2hLeaguePolicy.cycleOf(
        day: on ?? day,
        previousDrawn: drawn,
        previousRounds: rounds,
        previousJudged: judged,
      );

      expect(of(), _december);
      expect(of(rounds: 19), _january);
      expect(of(judged: true), _january);
      expect(of(drawn: false), _january);
      expect(of(on: DateTime.utc(2026, 12, 1)), _december);
    });

    test('cycleLastDayOf: a week ahead while rounds are left, else the '
        'month\'s last day', () {
      expect(
        H2hLeaguePolicy.cycleLastDayOf(
          monthStart: _december,
          today: DateTime.utc(2026, 12, 28),
          rounds: 15,
        ),
        DateTime.utc(2027, 1, 4),
      );
      expect(
        H2hLeaguePolicy.cycleLastDayOf(
          monthStart: _december,
          today: DateTime.utc(2026, 12, 28),
          rounds: 19,
        ),
        DateTime.utc(2026, 12, 31),
      );
      expect(
        H2hLeaguePolicy.cycleLastDayOf(
          monthStart: _november,
          today: DateTime.utc(2026, 11, 28),
          rounds: 10,
        ),
        DateTime.utc(2026, 11, 30),
      );
    });
  });
}
