import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/owner/switches/[key]/index.dart' as switch_route;
// ignore: always_use_package_imports
import '../../routes/owner/switches/index.dart' as switches_route;
import 'competition_route_harness.dart';

const _backup = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';
const _otherAdmin = '0c0c0c0c-0c0c-4c0c-8c0c-0c0c0c0c0c0c';

/// The owner seats: the harness admin and [_backup].
final class _Seats implements OwnerNotices {
  const _Seats();

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(kAdminId));

  @override
  Future<Result<bool>> isOwner(UserId user) async => Result.ok(
    user == const UserId(kAdminId) || user == const UserId(_backup),
  );

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

/// The `ops.owner_switches` rows, in memory.
final class _Rows implements OwnerSwitchSettings {
  bool on = true;
  String? reason;
  UserId? by;
  DateTime at = DateTime.utc(2026, 11, 20);
  int writes = 0;

  @override
  Future<Result<List<OwnerSwitchState>>> all() async => Result.ok([
    OwnerSwitchState(
      which: OwnerSwitch.crowning,
      isOn: on,
      reason: reason,
      changedBy: by,
      changedAt: at,
    ),
  ]);

  @override
  Future<Result<void>> set({
    required OwnerSwitch which,
    required bool on,
    required String reason,
    required UserId by,
  }) async {
    writes++;
    this.on = on;
    this.reason = reason;
    this.by = by;
    at = DateTime.utc(2026, 11, 30, 18);
    return const Result.ok(null);
  }
}

AuthenticatedUser _as(String id) =>
    AuthenticatedUser(userId: UserId(id), role: PlatformRole.admin);

// NK289_14
/// Script 289: the owners' switch board through its two routes and the
/// real use-case, as the composition root wires them.
void main() {
  late _Rows rows;

  CompositionRoot root({bool wired = true}) {
    rows = _Rows();
    return CompositionRoot.forTesting(
      ownerSwitchBoard: wired
          ? OwnerSwitchBoard(settings: rows, owners: const _Seats())
          : null,
    );
  }

  Future<Map<String, Object?>> put(
    CompositionRoot r,
    Object body, {
    String key = 'crowning',
    String who = kAdminId,
  }) async => decodeBody(
    await switch_route.onRequest(
      wireContext(
        root: r,
        principal: _as(who),
        method: HttpMethod.put,
        body: body,
      ),
      key,
    ),
  );

  test('an owner reads the crowning switch, never changed', () async {
    final response = await switches_route.onRequest(
      wireContext(
        root: root(),
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    final body = await decodeBody(response);
    final line =
        (body['switches']! as List<Object?>).single! as Map<Object?, Object?>;
    expect(line['key'], 'crowning');
    expect(line['is_on'], isTrue);
    expect(line['reason'], isNull);
    expect(line['changed_by'], isNull);
  });

  test('an owner turns the crowning off for a reason, and back', () async {
    final r = root();

    final off = await put(r, const {'is_on': false, 'reason': ' مراجعة '});

    expect(off['is_on'], isFalse);
    expect(off['reason'], 'مراجعة');
    expect(off['changed_by'], 'you');
    expect(off['changed_at'], '2026-11-30T18:00:00.000Z');
    expect(rows.by, const UserId(kAdminId));

    final seen = await decodeBody(
      await switches_route.onRequest(
        wireContext(root: r, principal: _as(_backup), method: HttpMethod.get),
      ),
    );
    final line =
        (seen['switches']! as List<Object?>).single! as Map<Object?, Object?>;
    expect(line['is_on'], isFalse);
    expect(line['changed_by'], 'other', reason: 'the backup seat reads it');

    final on = await put(r, const {
      'is_on': true,
      'reason': 'تحققت',
    }, who: _backup);
    expect(on['is_on'], isTrue);
    expect(rows.writes, 2);
  });

  test('a change from the SQL editor names no seat', () async {
    final r = root();
    rows
      ..on = false
      ..reason = 'إيقاف احترازي';

    final body = await decodeBody(
      await switches_route.onRequest(
        wireContext(
          root: r,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      ),
    );

    final line =
        (body['switches']! as List<Object?>).single! as Map<Object?, Object?>;
    expect(line['changed_by'], 'sql');
  });

  test('no reason, a bad flag or an unknown switch writes nothing', () async {
    final r = root();

    final blank = await put(r, const {'is_on': false, 'reason': '   '});
    final missing = await put(r, const {'is_on': false});
    final long = await put(r, {'is_on': false, 'reason': 'x' * 201});
    final flag = await put(r, const {'is_on': 'no', 'reason': 'x'});
    final unknown = await put(r, const {
      'is_on': false,
      'reason': 'x',
    }, key: 'no_such_switch');

    expect(blank['code'], 'owner.reason_required');
    expect(missing['code'], 'owner.reason_required');
    expect(long['code'], 'owner.reason_required');
    expect(flag['code'], 'owner.switch_invalid');
    expect(unknown['code'], 'owner.switch_unknown');
    expect(rows.writes, 0);
    expect(rows.on, isTrue);
  });

  test('an admin without a seat is refused and writes nothing', () async {
    final r = root();

    final response = await switch_route.onRequest(
      wireContext(
        root: r,
        principal: _as(_otherAdmin),
        method: HttpMethod.put,
        body: const {'is_on': false, 'reason': 'x'},
      ),
      'crowning',
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect(rows.writes, 0);
  });

  test('an unwired root is 503; another method 405', () async {
    final unwired = await switches_route.onRequest(
      wireContext(
        root: root(wired: false),
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );
    final post = await switches_route.onRequest(
      wireContext(root: root(), principal: adminPrincipal()),
    );
    final get = await switch_route.onRequest(
      wireContext(
        root: root(),
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
      'crowning',
    );

    expect(unwired.statusCode, HttpStatus.serviceUnavailable);
    expect(post.statusCode, HttpStatus.methodNotAllowed);
    expect(get.statusCode, HttpStatus.methodNotAllowed);
  });
}
