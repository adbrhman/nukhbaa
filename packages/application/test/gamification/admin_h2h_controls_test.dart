/// The admin's desk over the head-to-head league (batch 91): the controls
/// view, the settings, the excluded days, late seats, the month report and
/// a manual run of the jobs, each through the real use-case over in-memory
/// stores; and DrawH2hMonth / CloseH2hMonth reading the active days the
/// admin set.
library;

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'h2h_fakes.dart';

final _november = DateTime.utc(2026, 11);
const _league = H2hLeagueId('11111111-1111-4111-8111-111111111111');

DateTime _day(int d) => DateTime.utc(2026, 11, d);

/// Kickoff [hour]:00 Riyadh on November [d], as UTC.
DateTime _kickoff(int d, int hour) => DateTime.utc(2026, 11, d, hour - 3);

/// 19:00 Riyadh on November 10.
final _now = DateTime.utc(2026, 11, 10, 16);

/// In-memory [H2hControlStore] that keeps every write.
final class _Controls implements H2hControlStore {
  H2hSettings knobs = H2hSettings.defaults;
  final Set<DateTime> excluded = <DateTime>{};
  final List<H2hAdminAction> log = <H2hAdminAction>[];
  final List<String> seats = <String>[];
  AppError? seatError;

  @override
  Future<Result<H2hSettings>> settings() async => Result.ok(knobs);

  @override
  Future<Result<void>> saveSettings({
    required bool autoApprove,
    required int leadHours,
    required int minActiveDays,
    required UserId by,
  }) async {
    knobs = H2hSettings(
      autoApprove: autoApprove,
      leadHours: leadHours,
      minActiveDays: minActiveDays,
      updatedBy: by,
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<Set<DateTime>>> excludedDays({
    required DateTime from,
    required DateTime through,
  }) async => Result.ok({
    for (final d in excluded)
      if (!d.isBefore(from) && !d.isAfter(through)) d,
  });

  @override
  Future<Result<bool>> exclude({
    required DateTime day,
    required UserId by,
  }) async => Result.ok(excluded.add(day));

  @override
  Future<Result<bool>> include(DateTime day) async =>
      Result.ok(excluded.remove(day));

  @override
  Future<Result<void>> addSeat({
    required H2hLeagueId leagueId,
    required DateTime monthStart,
    required UserId userId,
    required int slot,
  }) async {
    final failure = seatError;
    if (failure != null) {
      return Result.err(failure);
    }
    seats.add('${leagueId.value}|${userId.value}|$slot');
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> record({
    required String id,
    required H2hAdminActionKind action,
    required UserId? by,
    required Map<String, Object?> detail,
  }) async {
    log.insert(
      0,
      H2hAdminAction(
        id: id,
        action: action,
        actor: by,
        detail: detail,
        actedAt: _now,
      ),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<List<H2hAdminAction>>> recentActions(int limit) async =>
      Result.ok(log.take(limit).toList());

  List<H2hAdminActionKind> get kinds => [for (final a in log) a.action];
}

/// One report per month asked for.
final class _Reports implements H2hMonthReportReader {
  final List<DateTime> asked = <DateTime>[];

  @override
  Future<Result<H2hMonthReport>> reportOf(DateTime monthStart) async {
    asked.add(monthStart);
    return Result.ok(
      H2hMonthReport(
        monthStart: monthStart,
        drawnAt: DateTime.utc(2026, 10, 31, 21, 5),
        isPilot: false,
        drawnSeats: 64,
        seats: 65,
        groupsByDivision: const {1: 1, 2: 1, 3: 1, 4: 1},
        closedAt: null,
        closedMembers: 0,
        outcomes: const <String, int>{},
      ),
    );
  }
}

/// A draw source that remembers the active days it was asked for.
final class _AskingSource implements H2hDrawSource {
  final List<int> minDaysAsked = <int>[];

  @override
  Future<Result<List<UserId>>> activeOrder({
    required DateTime monthStart,
    required int minActiveDays,
  }) async {
    minDaysAsked.add(minActiveDays);
    return Result.ok([for (var i = 1; i <= 4; i++) userNo(i)]);
  }

  @override
  Future<Result<List<H2hCarry>>> carriedFrom(DateTime monthStart) async =>
      const Result.ok(<H2hCarry>[]);

  @override
  Future<Result<List<UserId>>> pilotOrder(DateTime monthStart) async =>
      const Result.ok(<UserId>[]);
}

/// November drawn with one first-division group of four.
FakeH2hLeagueStore _drawnNovember() {
  final leagues = FakeH2hLeagueStore();
  leagues.drawn[_november] = [
    H2hDrawnGroup(
      leagueId: _league,
      group: H2hDrawGroup(
        division: H2hDivision.first,
        groupIndex: 0,
        seats: [
          for (var i = 0; i < 4; i++)
            H2hDrawSeat(userId: userNo(i + 1), slot: i),
        ],
      ),
    ),
  ];
  leagues.months[_november] = H2hMonthInfo(
    monthStart: _november,
    isPilot: false,
    seatedCount: 4,
  );
  leagues.seat(
    userNo(1),
    H2hSeat(
      leagueId: _league,
      monthStart: _november,
      division: H2hDivision.first,
      groupIndex: 0,
      slot: 0,
      capacity: H2hLeaguePolicy.groupCapacity,
      divisionGroups: 1,
      isPilot: false,
      joinedAt: _november,
    ),
  );
  return leagues;
}

({
  AdminH2hControls desk,
  _Controls controls,
  FakeH2hRoundStore rounds,
  FakeH2hLeagueStore leagues,
  _Reports reports,
})
_world({FakeH2hLeagueStore? leagues, FakeH2hRoundStore? rounds}) {
  final controls = _Controls();
  final roundStore = rounds ?? FakeH2hRoundStore();
  final leagueStore = leagues ?? FakeH2hLeagueStore();
  final reports = _Reports();
  final ids = SequenceIds();
  return (
    desk: AdminH2hControls(
      controls: controls,
      leagues: leagueStore,
      rounds: roundStore,
      reports: reports,
      profiles: NamingProfiles(),
      runRounds: RunH2hRounds(
        rounds: roundStore,
        leagues: leagueStore,
        idGenerator: ids,
        controls: controls,
      ),
      closeMonth: CloseH2hMonth(
        leagues: leagueStore,
        rounds: roundStore,
        sheets: FakeH2hSheetReader(),
        events: RecordingEvents(),
        idGenerator: ids,
        controls: controls,
      ),
      drawMonth: DrawH2hMonth(
        leagues: leagueStore,
        source: FakeH2hDrawSource(),
        idGenerator: ids,
        controls: controls,
      ),
      idGenerator: ids,
      clock: AtClock(_now),
    ),
    controls: controls,
    rounds: roundStore,
    leagues: leagueStore,
    reports: reports,
  );
}

H2hRound _round(int number, DateTime day) => H2hRound(
  id: H2hRoundId(
    '22222222-2222-4222-8222-${number.toString().padLeft(12, '0')}',
  ),
  monthStart: _november,
  number: number,
  day: day,
  fixtureCount: 9,
  approvedBy: null,
  lockedAt: null,
);

void main() {
  group('only an admin', () {
    test('every control refuses a player', () async {
      final world = _world(leagues: _drawnNovember());
      final desk = world.desk;

      final results = <Result<Object?>>[
        await desk.view(principal: player),
        await desk.saveSettings(
          principal: player,
          autoApprove: false,
          leadHours: 6,
          minActiveDays: 3,
        ),
        await desk.setDayExcluded(
          principal: player,
          day: _day(12),
          excluded: true,
        ),
        await desk.addSeat(
          principal: player,
          leagueId: _league,
          userId: userNo(9),
          slot: 5,
        ),
        await desk.report(principal: player),
        await desk.runJobs(principal: player),
      ];

      for (final result in results) {
        expect((result as Err<Object?>).error.code, 'auth.insufficient_role');
      }
      expect(world.controls.knobs.leadHours, 24);
      expect(world.controls.excluded, isEmpty);
      expect(world.controls.seats, isEmpty);
      expect(world.controls.log, isEmpty);
      expect(world.reports.asked, isEmpty);
    });
  });

  group('view', () {
    test('the days from today on: not started, or excluded', () async {
      final rounds = FakeH2hRoundStore()
        ..dayOf(_day(9), 8, _kickoff(9, 15)) // passed
        ..dayOf(_day(10), 7, _kickoff(10, 15)) // today, started
        ..dayOf(_day(11), 9, _kickoff(11, 15)) // round 1
        ..dayOf(_day(12), 3, _kickoff(12, 18)) // too few for a round
        ..addRound(_round(1, _day(11)));
      final world = _world(rounds: rounds);
      world.controls.excluded
        ..add(_day(14)) // no fixtures known yet
        ..add(_day(12))
        ..add(_day(3)); // before today: not shown
      await world.controls.record(
        id: 'line-1',
        action: H2hAdminActionKind.dayExcluded,
        by: admin.userId,
        detail: const {'day': '2026-11-14'},
      );

      final result = await world.desk.view(principal: admin);

      final view = (result as Ok<H2hControlsView>).value;
      expect(view.monthStart, _november);
      expect(view.settings.autoApprove, isTrue);
      expect(
        [for (final d in view.days) d.fixtures.day],
        [_day(11), _day(12), _day(14)],
      );
      expect([for (final d in view.days) d.excluded], [false, true, true]);
      expect([for (final d in view.days) d.round], [1, null, null]);
      expect(view.days.last.fixtures.fixtureCount, 0);
      expect(view.actions.single.action, H2hAdminActionKind.dayExcluded);
      expect(view.names[admin.userId], 'name ${admin.userId.value}');
    });

    test('next month starts from its first day', () async {
      final rounds = FakeH2hRoundStore()
        ..dayOf(DateTime.utc(2026, 12, 2), 6, DateTime.utc(2026, 12, 2, 12));
      final world = _world(rounds: rounds);

      final result = await world.desk.view(
        principal: admin,
        day: DateTime.utc(2026, 12),
      );

      final view = (result as Ok<H2hControlsView>).value;
      expect(view.monthStart, DateTime.utc(2026, 12));
      expect(
        [for (final d in view.days) d.fixtures.day],
        [DateTime.utc(2026, 12, 2)],
      );
    });
  });

  group('saveSettings', () {
    test('out of range is refused and nothing is saved', () async {
      final world = _world();

      final lead = await world.desk.saveSettings(
        principal: admin,
        autoApprove: true,
        leadHours: 25,
        minActiveDays: 5,
      );
      final days = await world.desk.saveSettings(
        principal: admin,
        autoApprove: true,
        leadHours: 24,
        minActiveDays: 0,
      );

      expect(
        (lead as Err<H2hSettings>).error.code,
        'h2h.settings_out_of_range',
      );
      expect(
        (days as Err<H2hSettings>).error.code,
        'h2h.settings_out_of_range',
      );
      expect(world.controls.knobs.leadHours, 24);
      expect(world.controls.log, isEmpty);
    });

    test('saved, logged, and answered as stored', () async {
      final world = _world();

      final result = await world.desk.saveSettings(
        principal: admin,
        autoApprove: false,
        leadHours: 6,
        minActiveDays: 3,
      );

      final stored = (result as Ok<H2hSettings>).value;
      expect(stored.autoApprove, isFalse);
      expect(stored.leadHours, 6);
      expect(stored.minActiveDays, 3);
      expect(stored.updatedBy, admin.userId);
      expect(world.controls.kinds, [H2hAdminActionKind.settingsSaved]);
      expect(world.controls.log.single.detail, {
        'auto_approve': false,
        'lead_hours': 6,
        'min_active_days': 3,
      });
    });
  });

  group('setDayExcluded', () {
    test('a day before today is refused', () async {
      final world = _world();

      final result = await world.desk.setDayExcluded(
        principal: admin,
        day: _day(9),
        excluded: true,
      );

      expect((result as Err<bool>).error.code, 'h2h.day_past');
      expect(world.controls.excluded, isEmpty);
    });

    test('only a change is logged', () async {
      final world = _world();

      final first = await world.desk.setDayExcluded(
        principal: admin,
        day: _day(12),
        excluded: true,
      );
      final again = await world.desk.setDayExcluded(
        principal: admin,
        day: _day(12),
        excluded: true,
      );
      final lifted = await world.desk.setDayExcluded(
        principal: admin,
        day: _day(12),
        excluded: false,
      );

      expect((first as Ok<bool>).value, isTrue);
      expect((again as Ok<bool>).value, isFalse);
      expect((lifted as Ok<bool>).value, isTrue);
      expect(world.controls.excluded, isEmpty);
      expect(world.controls.kinds, [
        H2hAdminActionKind.dayIncluded,
        H2hAdminActionKind.dayExcluded,
      ]);
      expect(world.controls.log.last.detail, {'day': '2026-11-12'});
    });

    test('today itself may still be excluded', () async {
      final world = _world();

      final result = await world.desk.setDayExcluded(
        principal: admin,
        day: _day(10),
        excluded: true,
      );

      expect((result as Ok<bool>).value, isTrue);
      expect(world.controls.excluded, {_day(10)});
    });
  });

  group('addSeat', () {
    test('a month not drawn is refused', () async {
      final world = _world();

      final result = await world.desk.addSeat(
        principal: admin,
        leagueId: _league,
        userId: userNo(9),
        slot: 5,
      );

      expect((result as Err<void>).error.code, 'h2h.month_not_drawn');
    });

    test('a judged month is refused', () async {
      final leagues = _drawnNovember()..closed[_november] = 4;
      final world = _world(leagues: leagues);

      final result = await world.desk.addSeat(
        principal: admin,
        leagueId: _league,
        userId: userNo(9),
        slot: 5,
      );

      expect((result as Err<void>).error.code, 'h2h.month_closed');
    });

    test(
      'a group of another month, a seat outside it, a seated player',
      () async {
        final world = _world(leagues: _drawnNovember());

        final group = await world.desk.addSeat(
          principal: admin,
          leagueId: const H2hLeagueId('99999999-9999-4999-8999-999999999999'),
          userId: userNo(9),
          slot: 5,
        );
        final outside = await world.desk.addSeat(
          principal: admin,
          leagueId: _league,
          userId: userNo(9),
          slot: H2hLeaguePolicy.groupCapacity,
        );
        final negative = await world.desk.addSeat(
          principal: admin,
          leagueId: _league,
          userId: userNo(9),
          slot: -1,
        );
        final seated = await world.desk.addSeat(
          principal: admin,
          leagueId: _league,
          userId: userNo(1),
          slot: 5,
        );

        expect((group as Err<void>).error.code, 'h2h.group_unknown');
        expect((outside as Err<void>).error.code, 'h2h.seat_outside_group');
        expect((negative as Err<void>).error.code, 'h2h.seat_outside_group');
        expect((seated as Err<void>).error.code, 'h2h.player_seated');
        expect(world.controls.seats, isEmpty);
        expect(world.controls.log, isEmpty);
      },
    );

    test('the seat is stored and logged', () async {
      final world = _world(leagues: _drawnNovember());

      final result = await world.desk.addSeat(
        principal: admin,
        leagueId: _league,
        userId: userNo(9),
        slot: 5,
      );

      expect(result.isOk, isTrue);
      expect(world.controls.seats, ['${_league.value}|${userNo(9).value}|5']);
      expect(world.controls.kinds, [H2hAdminActionKind.seatAdded]);
      expect(world.controls.log.single.detail, {
        'month': '2026-11-01',
        'league_id': _league.value,
        'user_id': userNo(9).value,
        'slot': 5,
      });
    });

    test('a refusal of the database is answered and not logged', () async {
      final world = _world(leagues: _drawnNovember());
      world.controls.seatError = const AppError.invariant(
        'h2h.seat_taken',
        'taken',
      );

      final result = await world.desk.addSeat(
        principal: admin,
        leagueId: _league,
        userId: userNo(9),
        slot: 2,
      );

      expect((result as Err<void>).error.code, 'h2h.seat_taken');
      expect(world.controls.log, isEmpty);
    });
  });

  group('report', () {
    test('the month containing the day asked for', () async {
      final world = _world();

      final result = await world.desk.report(
        principal: admin,
        day: DateTime.utc(2026, 12, 15),
      );

      expect((result as Ok<H2hMonthReport>).value.seats, 65);
      expect(world.reports.asked, [DateTime.utc(2026, 12)]);
    });

    test("today's month by default", () async {
      final world = _world();

      await world.desk.report(principal: admin);

      expect(world.reports.asked, [_november]);
    });
  });

  group('runJobs', () {
    test('runs the rounds, the closing and the draw, then logs', () async {
      final rounds = FakeH2hRoundStore()..dayOf(_day(11), 9, _kickoff(11, 15));
      final world = _world(rounds: rounds);

      final result = await world.desk.runJobs(principal: admin);

      final run = (result as Ok<H2hJobsRun>).value;
      expect(run.approved, 1);
      expect(run.locked, 0);
      expect(run.closedMonths, 0);
      expect(run.drawnSeats, 0);
      expect(rounds.byMonth[_november], hasLength(1));
      expect(world.controls.kinds, [H2hAdminActionKind.jobsRun]);
      expect(world.controls.log.single.detail, {
        'approved': 1,
        'locked': 0,
        'closed_months': 0,
        'drawn_seats': 0,
      });
    });

    test('automatic approval off is respected by the manual run', () async {
      final rounds = FakeH2hRoundStore()..dayOf(_day(11), 9, _kickoff(11, 15));
      final world = _world(rounds: rounds);
      world.controls.knobs = const H2hSettings(
        autoApprove: false,
        leadHours: 24,
        minActiveDays: 5,
      );

      final result = await world.desk.runJobs(principal: admin);

      expect((result as Ok<H2hJobsRun>).value.approved, 0);
      expect(rounds.byMonth[_november], isNull);
    });
  });

  group('the active days the admin set', () {
    test('DrawH2hMonth asks the source for them', () async {
      final controls = _Controls()
        ..knobs = const H2hSettings(
          autoApprove: true,
          leadHours: 24,
          minActiveDays: 3,
        );
      final withSettings = _AskingSource();
      final without = _AskingSource();

      await DrawH2hMonth(
        leagues: FakeH2hLeagueStore(),
        source: withSettings,
        idGenerator: SequenceIds(),
        controls: controls,
      ).call(now: DateTime.utc(2026, 11, 1, 1));
      await DrawH2hMonth(
        leagues: FakeH2hLeagueStore(),
        source: without,
        idGenerator: SequenceIds(),
      ).call(now: DateTime.utc(2026, 11, 1, 1));

      expect(withSettings.minDaysAsked, [3]);
      expect(without.minDaysAsked, [H2hLeaguePolicy.minActiveDays]);
    });

    test('CloseH2hMonth keeps a player who reached them', () async {
      // userNo(4) predicted on two days: out under the policy's five, in
      // under the admin's two.
      Future<Map<UserId, Map<String, Object?>>> close({
        _Controls? controls,
      }) async {
        final leagues = _drawnNovember();
        final rounds = FakeH2hRoundStore()
          ..addRound(
            H2hRound(
              id: const H2hRoundId('22222222-2222-4222-8222-222222222222'),
              monthStart: _november,
              number: 1,
              day: DateTime.utc(2026, 11, 8),
              fixtureCount: 8,
              approvedBy: null,
              lockedAt: DateTime.utc(2026, 11, 8, 12),
            ),
          );
        final sheets = FakeH2hSheetReader();
        sheets.sheets[_league] = H2hGroupSheet(
          members: [
            for (var i = 0; i < 4; i++)
              H2hMember(
                userId: userNo(i + 1),
                slot: i,
                joinedAt: DateTime.utc(2026, 11, 1, 0, i),
              ),
          ],
          scores: [
            for (var i = 0; i < 4; i++)
              H2hRoundScore(
                userId: userNo(i + 1),
                round: 1,
                points: 10 - 3 * i,
                exactCount: 0,
                predictedCount: 8,
              ),
          ],
          settledRounds: const <int>{1},
          voidRounds: const <int>{},
        );
        sheets.activeDays
          ..[userNo(1)] = 9
          ..[userNo(2)] = 6
          ..[userNo(3)] = 5
          ..[userNo(4)] = 2;
        final events = RecordingEvents();
        await CloseH2hMonth(
          leagues: leagues,
          rounds: rounds,
          sheets: sheets,
          events: events,
          idGenerator: SequenceIds(),
          controls: controls,
        ).call(now: DateTime.utc(2026, 12, 1, 0, 30));
        return {for (final e in events.recorded) e.userId: e.payload};
      }

      final byPolicy = await close();
      final byAdmin = await close(
        controls: _Controls()
          ..knobs = const H2hSettings(
            autoApprove: true,
            leadHours: 24,
            minActiveDays: 2,
          ),
      );

      expect(byPolicy[userNo(4)]!['outcome'], 'out');
      expect(byAdmin[userNo(4)]!['outcome'], isNot('out'));
      expect(byAdmin[userNo(4)]!['next_division'], isNotNull);
    });
  });
}
