import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';

const _user = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _leagueA = '11111111-1111-1111-1111-111111111111';
const _leagueB = '22222222-2222-2222-2222-222222222222';

/// 2026-09-20 21:00 UTC is 2026-09-21 00:00 in Riyadh -- a Sunday evening in
/// UTC that is already Monday in Riyadh. The instant proves the use-case
/// asks about the RIYADH week, not the UTC one.
final _sundayNight = DateTime.utc(2026, 9, 20, 21);
final _mondayWeek = DateTime.utc(2026, 9, 21);

const _principal = AuthenticatedUser(
  userId: UserId(_user),
  role: PlatformRole.user,
);

WeeklyLeagueSeat _seat({
  String id = _leagueA,
  WeeklyLeagueTier tier = WeeklyLeagueTier.bronze,
  int groupIndex = 0,
}) => WeeklyLeagueSeat(
  leagueId: WeeklyLeagueId(id),
  weekStart: _mondayWeek,
  tier: tier,
  groupIndex: groupIndex,
  joinedAt: DateTime.utc(2026, 9, 21, 9),
);

/// Scripted [WeeklyLeagueRepository] that records every question asked.
final class _FakeLeagues implements WeeklyLeagueRepository {
  _FakeLeagues({
    WeeklyLeagueSeat? existingSeat,
    WeeklyLeagueFinish? lastFinish,
    AppError? failSeatWith,
    AppError? failPlaceWith,
  }) : _existing = existingSeat,
       _finish = lastFinish,
       _seatFailure = failSeatWith,
       _placeFailure = failPlaceWith;

  final WeeklyLeagueSeat? _existing;
  final WeeklyLeagueFinish? _finish;
  final AppError? _seatFailure;
  final AppError? _placeFailure;

  DateTime? askedWeek;
  int seatCalls = 0;
  int placeCalls = 0;
  int finishCalls = 0;
  WeeklyLeagueTier? placedTier;
  WeeklyLeagueId? placedId;
  int? placedCapacity;

  @override
  Future<Result<WeeklyLeagueSeat?>> seatFor({
    required UserId userId,
    required DateTime weekStart,
  }) async {
    seatCalls++;
    askedWeek = weekStart;
    final failure = _seatFailure;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(_existing);
  }

  @override
  Future<Result<WeeklyLeagueFinish?>> lastFinishOf({
    required UserId userId,
  }) async {
    finishCalls++;
    return Result.ok(_finish);
  }

  @override
  Future<Result<WeeklyLeagueSeat>> place({
    required UserId userId,
    required DateTime weekStart,
    required WeeklyLeagueTier tier,
    required WeeklyLeagueId newLeagueId,
    required int capacity,
  }) async {
    placeCalls++;
    placedTier = tier;
    placedId = newLeagueId;
    placedCapacity = capacity;
    final failure = _placeFailure;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(_seat(id: newLeagueId.value, tier: tier));
  }
}

JoinWeeklyLeague _useCase(_FakeLeagues leagues, {String id = _leagueB}) =>
    JoinWeeklyLeague(
      leagues: leagues,
      idGenerator: FakeIdGenerator(<String>[id]),
      clock: FixedClock(_sundayNight),
    );

void main() {
  group('JoinWeeklyLeague', () {
    test('asks about the Riyadh week, not the UTC one', () async {
      final leagues = _FakeLeagues(existingSeat: _seat());
      await _useCase(leagues).call(principal: _principal);
      expect(leagues.askedWeek, _mondayWeek);
    });

    test('returns an existing seat and never places twice', () async {
      final leagues = _FakeLeagues(existingSeat: _seat());
      final result = await _useCase(leagues).call(principal: _principal);

      expect(result, isA<Ok<WeeklyLeagueSeat>>());
      expect((result as Ok<WeeklyLeagueSeat>).value.leagueId.value, _leagueA);
      expect(leagues.placeCalls, 0);
      expect(leagues.finishCalls, 0);
    });

    test('seats a player with no judged week in bronze', () async {
      final leagues = _FakeLeagues();
      final result = await _useCase(leagues).call(principal: _principal);

      expect(result, isA<Ok<WeeklyLeagueSeat>>());
      expect(leagues.placedTier, WeeklyLeagueTier.bronze);
      expect(leagues.placedId?.value, _leagueB);
      expect(leagues.placedCapacity, WeeklyLeaguePolicy.groupCapacity);
    });

    test('promotion moves the player up a tier', () async {
      final leagues = _FakeLeagues(
        lastFinish: const WeeklyLeagueFinish(
          tier: WeeklyLeagueTier.silver,
          outcome: WeeklyLeagueOutcome.promoted,
        ),
      );
      await _useCase(leagues).call(principal: _principal);
      expect(leagues.placedTier, WeeklyLeagueTier.gold);
    });

    test('relegation moves the player down a tier', () async {
      final leagues = _FakeLeagues(
        lastFinish: const WeeklyLeagueFinish(
          tier: WeeklyLeagueTier.silver,
          outcome: WeeklyLeagueOutcome.relegated,
        ),
      );
      await _useCase(leagues).call(principal: _principal);
      expect(leagues.placedTier, WeeklyLeagueTier.bronze);
    });

    test('holding keeps the tier', () async {
      final leagues = _FakeLeagues(
        lastFinish: const WeeklyLeagueFinish(
          tier: WeeklyLeagueTier.platinum,
          outcome: WeeklyLeagueOutcome.held,
        ),
      );
      await _useCase(leagues).call(principal: _principal);
      expect(leagues.placedTier, WeeklyLeagueTier.platinum);
    });

    test('a seat lookup failure is returned, not swallowed', () async {
      final leagues = _FakeLeagues(
        failSeatWith: const AppError.transient('db.down', 'down'),
      );
      final result = await _useCase(leagues).call(principal: _principal);

      expect(result, isA<Err<WeeklyLeagueSeat>>());
      expect((result as Err<WeeklyLeagueSeat>).error.code, 'db.down');
      expect(leagues.placeCalls, 0);
    });

    test('a placement failure is returned', () async {
      final leagues = _FakeLeagues(
        failPlaceWith: const AppError.transient('db.down', 'down'),
      );
      final result = await _useCase(leagues).call(principal: _principal);

      expect(result, isA<Err<WeeklyLeagueSeat>>());
      expect((result as Err<WeeklyLeagueSeat>).error.code, 'db.down');
    });
  });
}
