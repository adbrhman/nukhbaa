import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/weekly-league/index.dart' as route;
import 'competition_route_harness.dart';

const _leagueId = '11111111-1111-1111-1111-111111111111';

/// 2026-09-23 10:00 UTC is Wednesday 13:00 in Riyadh: inside the week that
/// opened on Monday 2026-09-21.
final _wednesday = DateTime.utc(2026, 9, 23, 10);
final _mondayWeek = DateTime.utc(2026, 9, 21);

final class _FixedClock implements Clock {
  const _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime nowUtc() => _now;
}

final class _FixedIds implements IdGenerator {
  @override
  String newUuid() => _leagueId;
}

/// A [WeeklyLeagueRepository] that either holds a seat or fails.
final class _FakeLeagues implements WeeklyLeagueRepository {
  _FakeLeagues({this.seat, this.failWith});

  final WeeklyLeagueSeat? seat;
  final AppError? failWith;

  @override
  Future<Result<WeeklyLeagueSeat?>> seatFor({
    required UserId userId,
    required DateTime weekStart,
  }) async {
    final failure = failWith;
    if (failure != null) {
      return Result.err(failure);
    }
    return Result.ok(seat);
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
  }) => throw StateError('the route test seats the caller in advance');
}

final class _FakeStandings implements WeeklyLeagueStandingsReader {
  _FakeStandings(this._entries);

  final List<WeeklyLeagueEntry> _entries;

  @override
  Future<Result<List<WeeklyLeagueEntry>>> entriesOf({
    required WeeklyLeagueId leagueId,
    required DateTime weekStart,
  }) async => Result.ok(_entries);
}

/// Names every member it is asked about `name-<id>`, and gives a picture
/// version to the ids listed in [avatars].
final class _FakeProfiles implements WeeklyLeagueProfileReader {
  _FakeProfiles({this.avatars = const {}});

  /// User id -> the version of that user's picture.
  final Map<String, DateTime> avatars;

  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async => Result.ok({
    for (final id in userIds)
      id: WeeklyLeagueMemberProfile(
        displayName: 'name-${id.value}',
        avatarUpdatedAt: avatars[id.value],
      ),
  });
}

WeeklyLeagueSeat _seat() => WeeklyLeagueSeat(
  leagueId: const WeeklyLeagueId(_leagueId),
  weekStart: _mondayWeek,
  tier: WeeklyLeagueTier.silver,
  groupIndex: 0,
  joinedAt: DateTime.utc(2026, 9, 21, 9),
);

WeeklyLeagueEntry _entry(String user, int points, {int exact = 0}) =>
    WeeklyLeagueEntry(
      userId: UserId(user),
      points: points,
      exactCount: exact,
      decidedCount: 4,
      joinedAt: DateTime.utc(2026, 9, 21, 9),
    );

String _id(int n) => '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

CompositionRoot _rootFor(
  _FakeLeagues leagues,
  _FakeStandings standings, {
  _FakeProfiles? profiles,
}) => CompositionRoot.forTesting(
  getMyWeeklyLeague: GetMyWeeklyLeague(
    join: JoinWeeklyLeague(
      leagues: leagues,
      idGenerator: _FixedIds(),
      clock: _FixedClock(_wednesday),
    ),
    standings: standings,
    profiles: profiles ?? _FakeProfiles(),
  ),
);

void main() {
  group('GET /me/weekly-league', () {
    test('returns the caller\'s group, ranked, with the zones', () async {
      // Eight members: the policy moves two each way.
      final standings = _FakeStandings([
        _entry(_id(1), 40),
        _entry(_id(2), 30),
        _entry(kNonMemberUserId, 20, exact: 2),
        _entry(_id(3), 10),
        _entry(_id(4), 9),
        _entry(_id(5), 8),
        _entry(_id(6), 7),
        _entry(_id(7), 0),
      ]);

      final response = await route.onRequest(
        wireContext(
          root: _rootFor(_FakeLeagues(seat: _seat()), standings),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['week_start'], '2026-09-21');
      expect(body['week_end'], '2026-09-27');
      expect(body['tier'], 2);
      expect(body['group_index'], 0);
      expect(body['my_rank'], 3);
      expect(body['promotion_zone'], 2);
      expect(body['relegation_zone'], 2);

      final entries = (body['entries']! as List).cast<Map<Object?, Object?>>();
      expect(entries, hasLength(8));
      expect([for (final e in entries) e['rank']], [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(entries.first['user_id'], _id(1));
      expect(entries.first['points'], 40);
      expect(entries.first['projected_outcome'], 'promoted');
      expect(entries[2]['user_id'], kNonMemberUserId);
      expect(entries[2]['exact_count'], 2);
      expect(entries[2]['projected_outcome'], 'held');
      expect(entries.last['projected_outcome'], 'relegated');
    });

    test('marks only the caller\'s own line', () async {
      final standings = _FakeStandings([
        _entry(_id(1), 5),
        _entry(kNonMemberUserId, 3),
      ]);

      final response = await route.onRequest(
        wireContext(
          root: _rootFor(_FakeLeagues(seat: _seat()), standings),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      final body = await decodeBody(response);
      final entries = (body['entries']! as List).cast<Map<Object?, Object?>>();
      expect([for (final e in entries) e['is_me']], [false, true]);
    });

    test('names every line and addresses the pictures that exist', () async {
      final standings = _FakeStandings([
        _entry(_id(1), 5),
        _entry(kNonMemberUserId, 3),
      ]);
      final version = DateTime.utc(2026, 9, 1);

      final response = await route.onRequest(
        wireContext(
          root: _rootFor(
            _FakeLeagues(seat: _seat()),
            standings,
            profiles: _FakeProfiles(avatars: {_id(1): version}),
          ),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      final body = await decodeBody(response);
      final entries = (body['entries']! as List).cast<Map<Object?, Object?>>();
      expect(entries.first['display_name'], 'name-${_id(1)}');
      expect(
        entries.first['avatar_url'],
        '/users/${_id(1)}/avatar?v=${version.millisecondsSinceEpoch}',
      );
      expect(entries.last['display_name'], 'name-$kNonMemberUserId');
      expect(entries.last['avatar_url'], isNull);
    });

    test('a failure is mapped through the error envelope', () async {
      final response = await route.onRequest(
        wireContext(
          root: _rootFor(
            _FakeLeagues(failWith: const AppError.transient('db.down', 'down')),
            _FakeStandings(const []),
          ),
          principal: nonMemberPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      final body = await decodeBody(response);
      expect(body['code'], 'db.down');
    });

    test('a non-GET method is 405', () async {
      final response = await route.onRequest(
        wireContext(
          root: _rootFor(_FakeLeagues(seat: _seat()), _FakeStandings(const [])),
          principal: nonMemberPrincipal(),
          method: HttpMethod.post,
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
