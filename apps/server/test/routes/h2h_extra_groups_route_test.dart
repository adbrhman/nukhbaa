/// `POST /admin/h2h/extra-groups` (2026-10-11) from the real handler, the
/// real `AddH2hGroups` and the real mapper over scripted stores: the
/// players waiting are seated twenty to a group into the next divisions,
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
import '../../routes/admin/h2h/extra-groups/index.dart' as extra_groups_route;
import 'competition_route_harness.dart';

const _firstGroup = '11111111-1111-4111-8111-111111111111';

final _october = DateTime.utc(2026, 10);

/// 02:00 Riyadh on October 11.
final _now = DateTime.utc(2026, 10, 10, 23);

List<UserId> _players(int count) => [
  for (var i = 0; i < count; i++)
    UserId('00000000-0000-4000-9000-${i.toString().padLeft(12, '0')}'),
];

/// October drawn with one first-division group, unless [drawn] is false.
final class _Leagues implements H2hLeagueStore {
  _Leagues({this.drawn = true});

  final bool drawn;

  @override
  Future<Result<H2hMonthInfo?>> monthOf(DateTime monthStart) async => Result.ok(
    drawn && monthStart == _october
        ? H2hMonthInfo(monthStart: _october, isPilot: true, seatedCount: 20)
        : null,
  );

  @override
  Future<Result<bool>> isClosed(DateTime monthStart) async =>
      const Result.ok(false);

  @override
  Future<Result<List<H2hGroupRef>>> groupsOf(DateTime monthStart) async =>
      const Result.ok([
        H2hGroupRef(
          leagueId: H2hLeagueId(_firstGroup),
          division: H2hDivision.first,
          groupIndex: 0,
          capacity: 20,
        ),
      ]);

  @override
  Future<Result<int>> draw({
    required DateTime monthStart,
    required bool isPilot,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) => throw UnimplementedError();

  @override
  Future<Result<H2hSeat?>> seatFor({
    required UserId userId,
    required DateTime monthStart,
  }) => throw UnimplementedError();

  @override
  Future<Result<DateTime?>> nextUnclosedMonth() => throw UnimplementedError();

  @override
  Future<Result<void>> markClosed({
    required DateTime monthStart,
    required int memberCount,
  }) => throw UnimplementedError();
}

/// [waiting] players wait; every write is kept.
final class _Extension implements H2hGroupExtension {
  _Extension(this.waiting);

  final List<UserId> waiting;
  final List<H2hDrawnGroup> written = <H2hDrawnGroup>[];

  @override
  Future<Result<List<UserId>>> waitingByParticipation({
    required DateTime monthStart,
    required int minActiveDays,
  }) async => Result.ok(waiting);

  @override
  Future<Result<int>> addGroups({
    required DateTime monthStart,
    required List<H2hDrawnGroup> groups,
    required int capacity,
  }) async {
    written.addAll(groups);
    var seats = 0;
    for (final g in groups) {
      seats += g.group.seats.length;
    }
    return Result.ok(seats);
  }
}

/// The default settings and the admin log.
final class _Controls implements H2hControlStore {
  final List<H2hAdminActionKind> log = <H2hAdminActionKind>[];

  @override
  Future<Result<H2hSettings>> settings() async =>
      const Result.ok(H2hSettings.defaults);

  @override
  Future<Result<void>> record({
    required String id,
    required H2hAdminActionKind action,
    required UserId? by,
    required Map<String, Object?> detail,
  }) async {
    log.add(action);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> saveSettings({
    required bool autoApprove,
    required int leadHours,
    required int minActiveDays,
    required UserId by,
  }) => throw UnimplementedError();

  @override
  Future<Result<Set<DateTime>>> excludedDays({
    required DateTime from,
    required DateTime through,
  }) => throw UnimplementedError();

  @override
  Future<Result<bool>> exclude({required DateTime day, required UserId by}) =>
      throw UnimplementedError();

  @override
  Future<Result<bool>> include(DateTime day) => throw UnimplementedError();

  @override
  Future<Result<void>> addSeat({
    required H2hLeagueId leagueId,
    required DateTime monthStart,
    required UserId userId,
    required int slot,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<H2hAdminAction>>> recentActions(int limit) =>
      throw UnimplementedError();
}

final class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String newUuid() {
    _next++;
    return '00000000-0000-4000-8000-${_next.toString().padLeft(12, '0')}';
  }
}

final class _At implements Clock {
  @override
  DateTime nowUtc() => _now;
}

CompositionRoot _root({
  required _Extension extension,
  _Controls? controls,
  bool drawn = true,
}) => CompositionRoot.forTesting(
  addH2hGroups: AddH2hGroups(
    leagues: _Leagues(drawn: drawn),
    extension: extension,
    controls: controls ?? _Controls(),
    idGenerator: _Ids(),
    clock: _At(),
  ),
);

void main() {
  group('POST /admin/h2h/extra-groups', () {
    test('three groups: second, third and open, logged', () async {
      final extension = _Extension(_players(72));
      final controls = _Controls();

      final response = await extra_groups_route.onRequest(
        wireContext(
          root: _root(extension: extension, controls: controls),
          principal: adminPrincipal(),
          body: const {'groups': 3},
        ),
      );

      expect(response.statusCode, HttpStatus.created);
      final body = await decodeBody(response);
      expect(body['month_start'], '2026-10-01');
      expect(body['seats'], 60);
      expect(body['waiting'], 12);
      final groups = (body['groups']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect([for (final g in groups) g['division']], [2, 3, 4]);
      expect([for (final g in groups) g['seats']], [20, 20, 20]);
      expect(extension.written, hasLength(3));
      expect(controls.log, [H2hAdminActionKind.groupsAdded]);
    });

    test('a count that is not a number is 400', () async {
      final response = await extra_groups_route.onRequest(
        wireContext(
          root: _root(extension: _Extension(_players(40))),
          principal: adminPrincipal(),
          body: const {'groups': '3'},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.groups_invalid');
    });

    test('a count out of range is 400', () async {
      final response = await extra_groups_route.onRequest(
        wireContext(
          root: _root(extension: _Extension(_players(40))),
          principal: adminPrincipal(),
          body: const {'groups': 11},
        ),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect((await decodeBody(response))['code'], 'h2h.groups_out_of_range');
    });

    test('a month not drawn is 409', () async {
      final response = await extra_groups_route.onRequest(
        wireContext(
          root: _root(extension: _Extension(_players(40)), drawn: false),
          principal: adminPrincipal(),
          body: const {'groups': 1},
        ),
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.month_not_drawn');
    });

    test('nobody waiting is 409', () async {
      final response = await extra_groups_route.onRequest(
        wireContext(
          root: _root(extension: _Extension(const [])),
          principal: adminPrincipal(),
          body: const {'groups': 1},
        ),
      );

      expect(response.statusCode, HttpStatus.conflict);
      expect((await decodeBody(response))['code'], 'h2h.groups_no_players');
    });

    test('a player is refused', () async {
      final extension = _Extension(_players(40));

      final response = await extra_groups_route.onRequest(
        wireContext(
          root: _root(extension: extension),
          principal: userPrincipal(),
          body: const {'groups': 1},
        ),
      );

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(extension.written, isEmpty);
    });

    test('a GET is 405', () async {
      final response = await extra_groups_route.onRequest(
        wireContext(
          root: _root(extension: _Extension(_players(40))),
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      );

      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });
}
