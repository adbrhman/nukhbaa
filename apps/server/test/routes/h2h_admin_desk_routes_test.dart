/// The admin's desk over the head-to-head league (batch 92) from the real
/// entry points: each route handler, the real use-cases and the real mapper
/// over scripted stores. The groups and a round of one group carry names
/// and stored points only; the controls change only what the admin sent,
/// and each refusal keeps its code.
library;

import 'dart:io';

import 'package:application/application.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/h2h/controls/index.dart' as controls_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/exclusions/index.dart' as exclusions_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/groups/[id]/rounds/[n]/index.dart'
    as group_round_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/groups/index.dart' as groups_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/jobs/index.dart' as jobs_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/players/[id]/index.dart' as player_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/report/index.dart' as report_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/seats/index.dart' as seats_route;
// ignore: always_use_package_imports
import '../../routes/admin/h2h/settings/index.dart' as settings_route;
import 'competition_route_harness.dart';

const _leagueId = '11111111-1111-4111-8111-111111111111';
const _otherLeague = '99999999-9999-4999-8999-999999999999';
const _u1 = '00000000-0000-4000-9000-000000000001';
const _u2 = '00000000-0000-4000-9000-000000000002';
const _u3 = '00000000-0000-4000-9000-000000000003';
const _u4 = '00000000-0000-4000-9000-000000000004';
const _members = [_u1, _u2, _u3];

final _novemberStart = DateTime.utc(2026, 11);

/// 2026-11-10 09:00 UTC: noon in Riyadh.
final _now = DateTime.utc(2026, 11, 10, 9);

H2hRound _round(int number, DateTime day, {required bool locked}) => H2hRound(
  id: H2hRoundId(
    '00000000-0000-4000-8000-${(100 + number).toString().padLeft(12, '0')}',
  ),
  monthStart: _novemberStart,
  number: number,
  day: day,
  fixtureCount: 6,
  approvedBy: null,
  lockedAt: locked ? day.add(const Duration(hours: 12)) : null,
);

/// Round 1 settled; round 2 on the 12th, not started.
final _rounds = [
  _round(1, DateTime.utc(2026, 11), locked: true),
  _round(2, DateTime.utc(2026, 11, 12), locked: false),
];

/// November is drawn with one second-division group of four seats; [_u1]
/// holds seat 0.
final class _Leagues implements H2hLeagueStore {
  @override
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart) async => Result.ok(
    monthStart == _novemberStart
        ? H2hMonthInfo(
            monthStart: _novemberStart,
            isPilot: false,
            seatedCount: 3,
          )
        : null,
  );

  @override
  Future<Result<bool>> isClosed(DateTime monthStart) async =>
      const Result.ok(false);

  @override
  Future<Result<int>> draw({
    required DateTime monthStart,
    required bool isPilot,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) async => const Result.ok(0);

  @override
  Future<Result<H2hSeat?>> seatFor({
    required UserId userId,
    required DateTime monthStart,
  }) async => Result.ok(
    userId.value == _u1 && monthStart == _novemberStart
        ? H2hSeat(
            leagueId: const H2hLeagueId(_leagueId),
            monthStart: _novemberStart,
            division: H2hDivision.second,
            groupIndex: 0,
            slot: 0,
            capacity: 4,
            divisionGroups: 1,
            isPilot: false,
            joinedAt: DateTime.utc(2026, 10, 31),
          )
        : null,
  );

  @override
  Future<Result<List<H2hGroupRef>>> groupsOf(DateTime monthStart) async =>
      Result.ok(
        monthStart == _novemberStart
            ? const [
                H2hGroupRef(
                  leagueId: H2hLeagueId(_leagueId),
                  division: H2hDivision.second,
                  groupIndex: 0,
                  capacity: 4,
                ),
              ]
            : const <H2hGroupRef>[],
      );

  @override
  Future<Result<DateTime?>> nextUnclosedMonth() async => const Result.ok(null);

  @override
  Future<Result<void>> markClosed({
    required DateTime monthStart,
    required int memberCount,
  }) async => const Result.ok(null);
}

final class _Rounds implements H2hRoundStore {
  @override
  Future<Result<List<H2hRound>>> roundsOf(DateTime monthStart) async =>
      Result.ok([
        for (final round in _rounds)
          if (round.monthStart == monthStart) round,
      ]);

  @override
  Future<Result<H2hDayFixtures>> dayFixtures(DateTime day) async => Result.ok(
    day == DateTime.utc(2026, 11, 12)
        ? H2hDayFixtures(
            day: day,
            fixtureCount: 6,
            firstKickoff: DateTime.utc(2026, 11, 12, 12),
          )
        : H2hDayFixtures(day: day, fixtureCount: 0, firstKickoff: null),
  );

  @override
  Future<Result<List<H2hDayFixtures>>> daysBetween({
    required DateTime from,
    required DateTime through,
  }) async => Result.ok([
    H2hDayFixtures(
      day: DateTime.utc(2026, 11, 12),
      fixtureCount: 6,
      firstKickoff: DateTime.utc(2026, 11, 12, 12),
    ),
  ]);

  @override
  Future<Result<void>> approve({
    required H2hRoundId id,
    required DateTime monthStart,
    required int number,
    required DateTime day,
    required int fixtureCount,
    required UserId? approvedBy,
  }) async => const Result.ok(null);

  @override
  Future<Result<void>> withdraw(H2hRoundId roundId) async =>
      const Result.ok(null);

  @override
  Future<Result<int>> lock({
    required H2hRoundId roundId,
    required DateTime day,
  }) async => const Result.ok(0);
}

/// Three members in seats 0..2; seat 3 is empty. Round 1 is settled.
final class _Sheets implements H2hSheetReader {
  @override
  Future<Result<H2hGroupSheet>> sheetOf({
    required H2hLeagueId leagueId,
    required List<H2hRound> rounds,
  }) async => Result.ok(
    H2hGroupSheet(
      members: [
        for (var i = 0; i < _members.length; i++)
          H2hMember(
            userId: UserId(_members[i]),
            slot: i,
            joinedAt: DateTime.utc(2026, 10, 31),
          ),
      ],
      scores: const [
        H2hRoundScore(
          userId: UserId(_u1),
          round: 1,
          points: 9,
          exactCount: 1,
          predictedCount: 6,
        ),
        H2hRoundScore(
          userId: UserId(_u2),
          round: 1,
          points: 4,
          exactCount: 0,
          predictedCount: 6,
        ),
        H2hRoundScore(
          userId: UserId(_u3),
          round: 1,
          points: 6,
          exactCount: 0,
          predictedCount: 6,
        ),
      ],
      settledRounds: const {1},
      voidRounds: const <int>{},
    ),
  );

  @override
  Future<Result<Map<UserId, int>>> activeDaysOf(DateTime monthStart) async =>
      const Result.ok(<UserId, int>{});
}

final class _Profiles implements WeeklyLeagueProfileReader {
  @override
  Future<Result<Map<UserId, WeeklyLeagueMemberProfile>>> profilesOf(
    List<UserId> userIds,
  ) async => Result.ok({
    for (final id in userIds)
      id: WeeklyLeagueMemberProfile(displayName: 'name-${id.value}'),
  });
}

/// The settings, the excluded days, the seats and the log, all kept.
final class _Controls implements H2hControlStore {
  H2hSettings knobs = H2hSettings.defaults;
  final Set<DateTime> excluded = {DateTime.utc(2026, 11, 14)};
  final List<String> seats = <String>[];
  final List<H2hAdminAction> log = [
    H2hAdminAction(
      id: 'line-1',
      action: H2hAdminActionKind.roundApproved,
      actor: const UserId(kAdminId),
      detail: const {'round': 2},
      actedAt: DateTime.utc(2026, 11, 9, 20),
    ),
  ];

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
      updatedAt: _now,
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
}

final class _Reports implements H2hMonthReportReader {
  @override
  Future<Result<H2hMonthReport>> reportOf(DateTime monthStart) async =>
      Result.ok(
        H2hMonthReport(
          monthStart: monthStart,
          drawnAt: DateTime.utc(2026, 10, 31, 21, 5),
          isPilot: false,
          drawnSeats: 3,
          seats: 4,
          groupsByDivision: const {2: 1},
          closedAt: null,
          closedMembers: 0,
          outcomes: const <String, int>{},
        ),
      );
}

final class _NoDraw implements H2hDrawSource {
  @override
  Future<Result<List<UserId>>> activeOrder({
    required DateTime monthStart,
    required int minActiveDays,
  }) async => const Result.ok(<UserId>[]);

  @override
  Future<Result<List<H2hCarry>>> carriedFrom(DateTime monthStart) async =>
      const Result.ok(<H2hCarry>[]);

  @override
  Future<Result<List<UserId>>> pilotOrder(DateTime monthStart) async =>
      const Result.ok(<UserId>[]);
}

final class _Events implements GamificationEventSink {
  @override
  Future<Result<void>> record(GamificationEvent event) async =>
      const Result.ok(null);
}

CompositionRoot _root(_Controls controls) {
  final leagues = _Leagues();
  final rounds = _Rounds();
  final sheets = _Sheets();
  final profiles = _Profiles();
  final clock = FixedClock(_now);
  final ids = ScriptedIdGenerator(const [
    '33333333-3333-4333-8333-333333333331',
    '33333333-3333-4333-8333-333333333332',
    '33333333-3333-4333-8333-333333333333',
  ]);
  return CompositionRoot.forTesting(
    h2hAdminDesk: H2hAdminDesk(
      groups: AdminGetH2hGroups(
        leagues: leagues,
        rounds: rounds,
        sheets: sheets,
        profiles: profiles,
        clock: clock,
      ),
      groupRound: AdminGetH2hGroupRound(
        leagues: leagues,
        rounds: rounds,
        sheets: sheets,
        profiles: profiles,
        clock: clock,
      ),
      player: AdminGetH2hPlayer(
        month: GetMyH2hMonth(
          league: GetMyH2hLeague(
            leagues: leagues,
            rounds: rounds,
            sheets: sheets,
            profiles: profiles,
            clock: clock,
          ),
          rounds: rounds,
          clock: clock,
        ),
      ),
      controls: AdminH2hControls(
        controls: controls,
        leagues: leagues,
        rounds: rounds,
        reports: _Reports(),
        profiles: profiles,
        runRounds: RunH2hRounds(
          rounds: rounds,
          leagues: leagues,
          idGenerator: ids,
          controls: controls,
        ),
        closeMonth: CloseH2hMonth(
          leagues: leagues,
          rounds: rounds,
          sheets: sheets,
          events: _Events(),
          idGenerator: ids,
          controls: controls,
        ),
        drawMonth: DrawH2hMonth(
          leagues: leagues,
          source: _NoDraw(),
          idGenerator: ids,
          controls: controls,
        ),
        idGenerator: ids,
        clock: clock,
      ),
    ),
  );
}

List<Map<Object?, Object?>> _list(Object? raw) =>
    (raw! as List).cast<Map<Object?, Object?>>();

Map<Object?, Object?> _map(Object? raw) => raw! as Map<Object?, Object?>;

void main() {
  group('GET /admin/h2h/groups', () {
    test('every group with its table and its empty seats', () async {
      final response = await groups_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['month_start'], '2026-11-01');
      expect(body['drawn'], true);
      expect(body['seated_count'], 3);
      expect([for (final r in _list(body['rounds'])) r['round']], [1, 2]);
      final group = _list(body['groups']).single;
      expect(group['league_id'], _leagueId);
      expect(group['division'], 2);
      expect(group['capacity'], 4);
      expect(group['free_slots'], [3]);
      final standings = _list(group['standings']);
      expect([for (final s in standings) s['user_id']], [_u1, _u3, _u2]);
      expect(standings.first['display_name'], 'name-$_u1');
      expect([for (final s in standings) s['is_me']], [false, false, false]);
    });

    test('a player is refused', () async {
      final response = await groups_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: userPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });

    test('a day that is not a date is 400', () async {
      final response = await groups_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
          queryParameters: const {'day': '2026-11'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.day_invalid');
    });
  });

  group('GET /admin/h2h/groups/{id}/rounds/{n}', () {
    test('names and stored points only', () async {
      final response = await group_round_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _leagueId,
        '1',
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['round'], 1);
      expect(body['status'], 'settled');
      final matches = _list(body['matches']);
      expect(matches, hasLength(2));
      for (final match in matches) {
        expect(match['home_name'], startsWith('name-'));
        expect(match['home_is_me'], false);
        final keys = [for (final k in match.keys) '$k'];
        expect(keys.where((k) => k.contains('goals')), isEmpty);
        expect(keys.where((k) => k.contains('pick')), isEmpty);
      }
    });

    test('a round number out of range is 400', () async {
      final response = await group_round_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _leagueId,
        '20',
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.round_invalid');
    });

    test('a group of another month is 409', () async {
      final response = await group_round_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _otherLeague,
        '1',
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.group_unknown');
    });

    test('a group id that is not a UUID is 400', () async {
      final response = await group_round_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        'not-a-uuid',
        '1',
      );

      expect(response.statusCode, HttpStatus.badRequest);
    });
  });

  group('GET /admin/h2h/players/{id}', () {
    test("the player's month as they see it", () async {
      final response = await player_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _u1,
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['state'], 'open');
      expect(body['division'], 2);
      final mine = [
        for (final s in _list(body['standings']))
          if (s['is_me'] == true) s['user_id'],
      ];
      expect(mine, [_u1]);
    });

    test('a player outside the draw is not_in_draw', () async {
      final response = await player_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        _u4,
      );

      expect((await decodeBody(response))['state'], 'not_in_draw');
    });

    test('an id that is not a UUID is 400', () async {
      final response = await player_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
        'nobody',
      );

      expect(response.statusCode, HttpStatus.badRequest);
    });
  });

  group('GET /admin/h2h/controls', () {
    test('the settings, the days and the log', () async {
      final response = await controls_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['month_start'], '2026-11-01');
      final settings = _map(body['settings']);
      expect(settings['auto_approve'], true);
      expect(settings['lead_hours'], 24);
      expect(settings['min_active_days'], 5);
      expect(settings['lead_hours_max'], 24);
      expect(settings['min_active_days_max'], 28);
      final days = _list(body['days']);
      expect([for (final d in days) d['day']], ['2026-11-12', '2026-11-14']);
      expect([for (final d in days) d['excluded']], [false, true]);
      expect([for (final d in days) d['round']], [2, null]);
      expect(days.first['first_kickoff'], '2026-11-12T12:00:00.000Z');
      final action = _list(body['actions']).single;
      expect(action['action'], 'round_approved');
      expect(action['actor_name'], 'name-$kAdminId');
      expect(action['detail'], {'round': 2});
    });
  });

  group('PUT /admin/h2h/settings', () {
    test('stored, logged and answered', () async {
      final controls = _Controls();
      final response = await settings_route.onRequest(
        wireContext(
          root: _root(controls),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {
            'auto_approve': false,
            'lead_hours': 6,
            'min_active_days': 3,
          },
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['auto_approve'], false);
      expect(body['lead_hours'], 6);
      expect(body['min_active_days'], 3);
      expect(controls.knobs.leadHours, 6);
      expect(controls.log.first.action, H2hAdminActionKind.settingsSaved);
    });

    test('a mistyped field is 400', () async {
      final response = await settings_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {
            'auto_approve': 'yes',
            'lead_hours': 6,
            'min_active_days': 3,
          },
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.settings_invalid');
    });

    test('a value out of range is 400', () async {
      final controls = _Controls();
      final response = await settings_route.onRequest(
        wireContext(
          root: _root(controls),
          principal: adminPrincipal(),
          method: HttpMethod.put,
          body: const {
            'auto_approve': true,
            'lead_hours': 48,
            'min_active_days': 3,
          },
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.settings_out_of_range');
      expect(controls.knobs.leadHours, 24);
    });

    test('a POST is 405', () async {
      final response = await settings_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          body: const <String, Object?>{},
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('POST /admin/h2h/exclusions', () {
    test('a day is excluded and the change answered', () async {
      final controls = _Controls();
      final response = await exclusions_route.onRequest(
        wireContext(
          root: _root(controls),
          principal: adminPrincipal(),
          body: const {'day': '2026-11-12', 'excluded': true},
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['changed'], true);
      expect(controls.excluded, contains(DateTime.utc(2026, 11, 12)));
      expect(controls.log.first.action, H2hAdminActionKind.dayExcluded);
    });

    test('lifting an exclusion', () async {
      final controls = _Controls();
      final response = await exclusions_route.onRequest(
        wireContext(
          root: _root(controls),
          principal: adminPrincipal(),
          body: const {'day': '2026-11-14', 'excluded': false},
        ),
      );

      expect((await decodeBody(response))['changed'], true);
      expect(controls.excluded, isEmpty);
    });

    test('a day before today is 400', () async {
      final response = await exclusions_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          body: const {'day': '2026-11-01', 'excluded': true},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.day_past');
    });

    test('a missing choice is 400', () async {
      final response = await exclusions_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          body: const {'day': '2026-11-12'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.excluded_invalid');
    });
  });

  group('POST /admin/h2h/seats', () {
    test('a late player takes the empty seat', () async {
      final controls = _Controls();
      final response = await seats_route.onRequest(
        wireContext(
          root: _root(controls),
          principal: adminPrincipal(),
          body: const {'league_id': _leagueId, 'user_id': _u4, 'slot': 3},
        ),
      );

      expect(response.statusCode, HttpStatus.created);
      expect((await decodeBody(response))['seated'], true);
      expect(controls.seats, ['$_leagueId|$_u4|3']);
      expect(controls.log.first.action, H2hAdminActionKind.seatAdded);
    });

    test('a group of another month is 409', () async {
      final response = await seats_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          body: const {'league_id': _otherLeague, 'user_id': _u4, 'slot': 3},
        ),
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.group_unknown');
    });

    test('a seated player is 409', () async {
      final response = await seats_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          body: const {'league_id': _leagueId, 'user_id': _u1, 'slot': 3},
        ),
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.player_seated');
    });

    test('a slot that is not a number is 400', () async {
      final response = await seats_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          body: const {'league_id': _leagueId, 'user_id': _u4, 'slot': '3'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.slot_invalid');
    });

    test('a user id that is not a UUID is 400', () async {
      final response = await seats_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          body: const {'league_id': _leagueId, 'user_id': 'x', 'slot': 3},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
    });
  });

  group('GET /admin/h2h/report', () {
    test('the month containing the day', () async {
      final response = await report_route.onRequest(
        wireContext(
          root: _root(_Controls()),
          principal: adminPrincipal(),
          method: HttpMethod.get,
          queryParameters: const {'day': '2026-11-20'},
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(body['month_start'], '2026-11-01');
      expect(body['drawn'], true);
      expect(body['drawn_seats'], 3);
      expect(body['seats'], 4);
      expect(body['groups_by_division'], {'2': 1});
      expect(body['closed'], false);
    });
  });

  group('POST /admin/h2h/jobs', () {
    test('runs the jobs and logs the run', () async {
      final controls = _Controls();
      final response = await jobs_route.onRequest(
        wireContext(root: _root(controls), principal: adminPrincipal()),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = await decodeBody(response);
      expect(
        body.keys,
        containsAll(<String>[
          'approved',
          'locked',
          'closed_months',
          'drawn_seats',
        ]),
      );
      expect(controls.log.first.action, H2hAdminActionKind.jobsRun);
    });

    test('a player is refused', () async {
      final controls = _Controls();
      final response = await jobs_route.onRequest(
        wireContext(root: _root(controls), principal: userPrincipal()),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(controls.log, hasLength(1));
    });
  });
}
