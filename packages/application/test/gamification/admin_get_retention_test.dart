import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _user = '11111111-2222-3333-4444-555555555555';

final class _FixedClock implements Clock {
  const _FixedClock(this.now);

  final DateTime now;

  @override
  DateTime nowUtc() => now;
}

final class _FakeReader implements RetentionReader {
  List<WeeklyActivity> weekAnswer = const [];
  List<RetentionCohort> cohortAnswer = const [];
  bool failWeeks = false;
  bool failCohorts = false;
  int calls = 0;
  DateTime? weeksFrom;
  DateTime? weeksThrough;
  DateTime? cohortsFrom;
  DateTime? cohortsToday;

  @override
  Future<Result<List<WeeklyActivity>>> weeks({
    required DateTime from,
    required DateTime through,
  }) async {
    calls++;
    weeksFrom = from;
    weeksThrough = through;
    if (failWeeks) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    return Result.ok(weekAnswer);
  }

  @override
  Future<Result<List<RetentionCohort>>> cohorts({
    required DateTime from,
    required DateTime today,
  }) async {
    calls++;
    cohortsFrom = from;
    cohortsToday = today;
    if (failCohorts) {
      return const Result.err(AppError.transient('db.down', 'down'));
    }
    return Result.ok(cohortAnswer);
  }
}

const _player = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
);
const _admin = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.admin,
);

WeeklyActivity _activity(DateTime week) => WeeklyActivity(
  weekStart: week,
  activeUsers: 10,
  active3Plus: 4,
  leagueActive: 5,
  leagueActive3Plus: 3,
  leagueMembers: 4,
  leagueReturned: 3,
);

void main() {
  // Monday 2026-09-28, 22:30 UTC: already Tuesday 2026-09-29 in Riyadh.
  final now = DateTime.utc(2026, 9, 28, 22, 30);
  final today = DateTime.utc(2026, 9, 29);
  final current = DateTime.utc(2026, 9, 28);

  AdminGetRetention use(_FakeReader reader) =>
      AdminGetRetention(reader: reader, clock: _FixedClock(now));

  test('the window runs back from the Riyadh week in progress', () async {
    final reader = _FakeReader();

    final result = await use(reader)(principal: _admin, weeks: 4);

    final stats = (result as Ok<RetentionStats>).value;
    expect(stats.today, today, reason: 'the day is read in Riyadh');
    expect(reader.weeksThrough, current);
    expect(reader.weeksFrom, DateTime.utc(2026, 9, 7));
    expect(reader.cohortsFrom, DateTime.utc(2026, 9, 7));
    expect(reader.cohortsToday, today);
    expect(stats.weeks.map((w) => w.weekStart), [
      DateTime.utc(2026, 9, 28),
      DateTime.utc(2026, 9, 21),
      DateTime.utc(2026, 9, 14),
      DateTime.utc(2026, 9, 7),
    ]);
  });

  test('a week nobody played still reads, as zeros', () async {
    final reader = _FakeReader()
      ..weekAnswer = [_activity(DateTime.utc(2026, 9, 14))]
      ..cohortAnswer = [
        RetentionCohort(
          weekStart: DateTime.utc(2026, 9, 14),
          users: 6,
          day1Eligible: 6,
          day1: 3,
          day7Eligible: 6,
          day7: 2,
          day14Eligible: 2,
          day14: 1,
          week4Eligible: 0,
          week4: 0,
        ),
      ];

    final result = await use(reader)(principal: _admin, weeks: 3);

    final stats = (result as Ok<RetentionStats>).value;
    expect(stats.weeks.map((w) => w.activeUsers), [0, 0, 10]);
    expect(stats.cohorts.map((c) => c.users), [0, 0, 6]);
    expect(stats.cohorts.last.day7, 2);
  });

  test('league seats held again read only once the next week ended', () async {
    final reader = _FakeReader()
      ..weekAnswer = [
        _activity(DateTime.utc(2026, 9, 28)),
        _activity(DateTime.utc(2026, 9, 21)),
        _activity(DateTime.utc(2026, 9, 14)),
      ];

    final result = await use(reader)(principal: _admin, weeks: 3);

    final weeks = (result as Ok<RetentionStats>).value.weeks;
    expect(weeks.map((w) => w.complete), [false, true, true]);
    expect(
      weeks.map((w) => w.leagueReturned),
      [null, null, 3],
      reason: 'the week of 21/9 is followed by the week still in progress',
    );
  });

  test('the window is clamped', () async {
    final reader = _FakeReader();
    final run = use(reader);

    final none = await run(principal: _admin);
    expect(
      (none as Ok<RetentionStats>).value.weeks,
      hasLength(AdminGetRetention.defaultWeeks),
    );
    final zero = await run(principal: _admin, weeks: 0);
    expect(
      (zero as Ok<RetentionStats>).value.weeks,
      hasLength(AdminGetRetention.defaultWeeks),
    );
    final huge = await run(principal: _admin, weeks: 500);
    expect(
      (huge as Ok<RetentionStats>).value.weeks,
      hasLength(AdminGetRetention.maxWeeks),
    );
  });

  test('a player is refused before anything is read', () async {
    final reader = _FakeReader();

    final result = await use(reader)(principal: _player);

    expect(result.isErr, isTrue);
    expect(
      (result as Err<RetentionStats>).error.code,
      'auth.insufficient_role',
    );
    expect(reader.calls, 0);
  });

  test('a failed read is the answer', () async {
    final weeksDown = await use(_FakeReader()..failWeeks = true)(
      principal: _admin,
    );
    expect(weeksDown.isErr, isTrue);

    final cohortsDown = await use(_FakeReader()..failCohorts = true)(
      principal: _admin,
    );
    expect(cohortsDown.isErr, isTrue);
  });
}
