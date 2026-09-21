import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../competition/fakes.dart';

const _me = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
const _leagueA = '11111111-1111-1111-1111-111111111111';
const _leagueB = '22222222-2222-2222-2222-222222222222';

/// 2026-09-23 10:00 UTC is Wednesday 13:00 in Riyadh: inside the week that
/// opened on Monday 2026-09-21.
final _wednesday = DateTime.utc(2026, 9, 23, 10);
final _mondayWeek = DateTime.utc(2026, 9, 21);

const _principal = AuthenticatedUser(
  userId: UserId(_me),
  role: PlatformRole.user,
);

/// A distinct, well-formed user id for member number [n].
String _id(int n) => '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

WeeklyLeagueSeat _seat({
  String id = _leagueA,
  WeeklyLeagueTier tier = WeeklyLeagueTier.bronze,
}) => WeeklyLeagueSeat(
  leagueId: WeeklyLeagueId(id),
  weekStart: _mondayWeek,
  tier: tier,
  groupIndex: 0,
  joinedAt: DateTime.utc(2026, 9, 21, 9),
);

WeeklyLeagueEntry _entry(
  String user, {
  int points = 0,
  int exact = 0,
  int decided = 0,
  int joinedHour = 9,
}) => WeeklyLeagueEntry(
  userId: UserId(user),
  points: points,
  exactCount: exact,
  decidedCount: decided,
  joinedAt: DateTime.utc(2026, 9, 21, joinedHour),
);

/// [size] members, the caller among them, all on the same points so that
/// nothing but the size decides the zones.
List<WeeklyLeagueEntry> _group(int size) => [
  _entry(_me, points: 1),
  for (var i = 1; i < size; i++) _entry(_id(i), points: 1),
];

/// Scripted [WeeklyLeagueRepository]: the seat is either already held or
/// placed on demand.
final class _FakeLeagues implements WeeklyLeagueRepository {
  _FakeLeagues({this.existingSeat, this.failSeatWith});

  final WeeklyLeagueSeat? existingSeat;
  final AppError? failSeatWith;

  int placeCalls = 0;

  @override
  Future<Result<WeeklyLeagueSeat?>> seatFor({
    required UserId userId,
    required DateTime weekStart,
  }) async {
    final failure = failSeatWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(existingSeat);
  }

  @override
  Future<Result<WeeklyLeagueFinish?>> lastFinishOf({
    required UserId userId,
  }) async => const Result.ok(null);

  @override
  Future<Result<WeeklyLeagueSeat>> place({
    required UserId userId,
    required DateTime weekStart,
    required WeeklyLeagueTier tier,
    required WeeklyLeagueId newLeagueId,
    required int capacity,
  }) async {
    placeCalls++;
    return Result.ok(_seat(id: newLeagueId.value, tier: tier));
  }
}

/// Scripted [WeeklyLeagueStandingsReader] that records what it was asked.
final class _FakeStandings implements WeeklyLeagueStandingsReader {
  _FakeStandings(this._entries, {this.failWith});

  final List<WeeklyLeagueEntry> _entries;
  final AppError? failWith;

  int calls = 0;
  WeeklyLeagueId? askedLeague;
  DateTime? askedWeek;

  @override
  Future<Result<List<WeeklyLeagueEntry>>> entriesOf({
    required WeeklyLeagueId leagueId,
    required DateTime weekStart,
  }) async {
    calls++;
    askedLeague = leagueId;
    askedWeek = weekStart;
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(_entries);
  }
}

/// Scripted [WeeklyLeagueProfileReader] that records what it was asked and
/// names everyone it is asked about, except the ids it is told not to know.
final class _FakeProfiles implements WeeklyLeagueProfileReader {
  _FakeProfiles({
    this.avatars = const {},
    this.unknown = const {},
    this.failWith,
  });

  /// User id -> the version of that user's picture.
  final Map<String, DateTime> avatars;

  /// User ids the reader has no profile for.
  final Set<String> unknown;
  final AppError? failWith;

  int calls = 0;
  List<UserId>? askedFor;

  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async {
    calls++;
    askedFor = userIds;
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok({
      for (final id in userIds)
        if (!unknown.contains(id.value))
          id: WeeklyLeagueMemberProfile(
            displayName: 'name-${id.value}',
            avatarUpdatedAt: avatars[id.value],
          ),
    });
  }
}

GetMyWeeklyLeague _useCase(
  _FakeLeagues leagues,
  _FakeStandings standings, {
  _FakeProfiles? profiles,
}) => GetMyWeeklyLeague(
  join: JoinWeeklyLeague(
    leagues: leagues,
    idGenerator: FakeIdGenerator(<String>[_leagueB]),
    clock: FixedClock(_wednesday),
  ),
  standings: standings,
  profiles: profiles ?? _FakeProfiles(),
);

Future<MyWeeklyLeague> _read({
  required WeeklyLeagueTier tier,
  required List<WeeklyLeagueEntry> entries,
}) async {
  final result = await _useCase(
    _FakeLeagues(existingSeat: _seat(tier: tier)),
    _FakeStandings(entries),
  ).call(principal: _principal);
  return (result as Ok<MyWeeklyLeague>).value;
}

void main() {
  group('GetMyWeeklyLeague', () {
    test('seats the caller before it reads the group', () async {
      final leagues = _FakeLeagues();
      final standings = _FakeStandings([_entry(_me, points: 4)]);

      final result = await _useCase(
        leagues,
        standings,
      ).call(principal: _principal);

      expect(result, isA<Ok<MyWeeklyLeague>>());
      expect(leagues.placeCalls, 1);
      expect(standings.askedLeague?.value, _leagueB);
      expect(standings.askedWeek, _mondayWeek);
    });

    test('reads the group of an existing seat without placing again', () async {
      final leagues = _FakeLeagues(existingSeat: _seat());
      final standings = _FakeStandings([_entry(_me, points: 4)]);

      final result = await _useCase(
        leagues,
        standings,
      ).call(principal: _principal);

      final league = (result as Ok<MyWeeklyLeague>).value;
      expect(leagues.placeCalls, 0);
      expect(standings.askedLeague?.value, _leagueA);
      expect(league.seat.leagueId.value, _leagueA);
      expect(league.readerId, const UserId(_me));
    });

    test('ranks by the published total order and finds the caller', () async {
      final league = await _read(
        tier: WeeklyLeagueTier.silver,
        entries: [
          // Same points as the caller, more exact calls: ahead.
          _entry(_id(2), points: 10, exact: 2, decided: 4),
          _entry(_me, points: 10, exact: 1, decided: 3),
          // Same points and exact calls, more decided fixtures: behind.
          _entry(_id(3), points: 10, exact: 1, decided: 5),
          _entry(_id(1), points: 30, exact: 3, decided: 6),
        ],
      );

      expect(
        [for (final p in league.placings) p.entry.userId.value],
        [_id(1), _id(2), _me, _id(3)],
      );
      expect([for (final p in league.placings) p.rank], [1, 2, 3, 4]);
      expect(league.myRank, 3);
      expect(league.size, 4);
    });

    test('a group of eight moves two places each way', () async {
      final league = await _read(
        tier: WeeklyLeagueTier.silver,
        entries: _group(8),
      );
      expect(league.promotionZone, 2);
      expect(league.relegationZone, 2);
    });

    test('a full group moves five places each way', () async {
      final league = await _read(
        tier: WeeklyLeagueTier.silver,
        entries: _group(20),
      );
      expect(league.promotionZone, 5);
      expect(league.relegationZone, 5);
    });

    test('a group too small to move anyone has no zones', () async {
      final league = await _read(
        tier: WeeklyLeagueTier.silver,
        entries: _group(3),
      );
      expect(league.promotionZone, 0);
      expect(league.relegationZone, 0);
    });

    test('nothing is relegated out of the bottom tier', () async {
      final league = await _read(
        tier: WeeklyLeagueTier.bronze,
        entries: _group(8),
      );
      expect(league.promotionZone, 2);
      expect(league.relegationZone, 0);
    });

    test('nothing is promoted out of the top tier', () async {
      final league = await _read(
        tier: WeeklyLeagueTier.elite,
        entries: _group(8),
      );
      expect(league.promotionZone, 0);
      expect(league.relegationZone, 2);
    });

    test('each row carries the outcome the policy would give it', () async {
      final league = await _read(
        tier: WeeklyLeagueTier.silver,
        entries: [
          _entry(_id(1), points: 9),
          _entry(_id(2), points: 5),
          _entry(_me, points: 2),
          _entry(_id(3)),
        ],
      );

      expect(
        [for (final p in league.placings) p.outcome],
        [
          WeeklyLeagueOutcome.promoted,
          WeeklyLeagueOutcome.held,
          WeeklyLeagueOutcome.held,
          WeeklyLeagueOutcome.relegated,
        ],
      );
    });

    test('a member who scored nothing is not projected to promote', () async {
      final league = await _read(
        tier: WeeklyLeagueTier.silver,
        entries: [_entry(_me), _entry(_id(1)), _entry(_id(2)), _entry(_id(3))],
      );

      expect(league.placings.first.outcome, WeeklyLeagueOutcome.held);
    });

    test('a caller missing from the standings is an error', () async {
      final result = await _useCase(
        _FakeLeagues(existingSeat: _seat()),
        _FakeStandings([_entry(_id(1), points: 3)]),
      ).call(principal: _principal);

      expect(result, isA<Err<MyWeeklyLeague>>());
      expect(
        (result as Err<MyWeeklyLeague>).error.code,
        'gamification.weekly_league_member_missing',
      );
    });

    test('a seating failure is returned and the group is not read', () async {
      final standings = _FakeStandings([_entry(_me)]);
      final result = await _useCase(
        _FakeLeagues(failSeatWith: const AppError.transient('db.down', 'down')),
        standings,
      ).call(principal: _principal);

      expect(result, isA<Err<MyWeeklyLeague>>());
      expect((result as Err<MyWeeklyLeague>).error.code, 'db.down');
      expect(standings.calls, 0);
    });

    test('a standings failure is returned, not swallowed', () async {
      final result = await _useCase(
        _FakeLeagues(existingSeat: _seat()),
        _FakeStandings(
          const [],
          failWith: const AppError.transient('db.down', 'down'),
        ),
      ).call(principal: _principal);

      expect(result, isA<Err<MyWeeklyLeague>>());
      expect((result as Err<MyWeeklyLeague>).error.code, 'db.down');
    });

    test(
      'asks for the profiles of exactly the members it ranked, once',
      () async {
        final profiles = _FakeProfiles();

        final result = await _useCase(
          _FakeLeagues(existingSeat: _seat()),
          _FakeStandings([
            _entry(_me, points: 4),
            _entry(_id(1)),
            _entry(_id(2)),
          ]),
          profiles: profiles,
        ).call(principal: _principal);

        expect(result, isA<Ok<MyWeeklyLeague>>());
        expect(profiles.calls, 1);
        expect(profiles.askedFor?.map((id) => id.value).toSet(), {
          _me,
          _id(1),
          _id(2),
        });
      },
    );

    test('hands back the name and picture version of each member', () async {
      final version = DateTime.utc(2026, 9, 1, 8);

      final result = await _useCase(
        _FakeLeagues(existingSeat: _seat()),
        _FakeStandings([_entry(_me, points: 4), _entry(_id(1))]),
        profiles: _FakeProfiles(avatars: {_me: version}),
      ).call(principal: _principal);

      final league = (result as Ok<MyWeeklyLeague>).value;
      expect(league.profiles[const UserId(_me)]?.displayName, 'name-$_me');
      expect(league.profiles[const UserId(_me)]?.avatarUpdatedAt, version);
      expect(league.profiles[UserId(_id(1))]?.avatarUpdatedAt, isNull);
    });

    test('a member the reader does not know stays on the table', () async {
      final result = await _useCase(
        _FakeLeagues(existingSeat: _seat()),
        _FakeStandings([_entry(_me, points: 4), _entry(_id(1))]),
        profiles: _FakeProfiles(unknown: {_id(1)}),
      ).call(principal: _principal);

      final league = (result as Ok<MyWeeklyLeague>).value;
      expect(league.size, 2);
      expect(league.profiles.containsKey(UserId(_id(1))), isFalse);
      expect(league.profiles.containsKey(const UserId(_me)), isTrue);
    });

    test('a profile failure is returned, not swallowed', () async {
      final result = await _useCase(
        _FakeLeagues(existingSeat: _seat()),
        _FakeStandings([_entry(_me, points: 4)]),
        profiles: _FakeProfiles(
          failWith: const AppError.transient('db.down', 'down'),
        ),
      ).call(principal: _principal);

      expect(result, isA<Err<MyWeeklyLeague>>());
      expect((result as Err<MyWeeklyLeague>).error.code, 'db.down');
    });

    test(
      'the profiles are not read for a caller missing from the group',
      () async {
        final profiles = _FakeProfiles();

        final result = await _useCase(
          _FakeLeagues(existingSeat: _seat()),
          _FakeStandings([_entry(_id(1), points: 3)]),
          profiles: profiles,
        ).call(principal: _principal);

        expect(result, isA<Err<MyWeeklyLeague>>());
        expect(profiles.calls, 0);
      },
    );
  });
}
