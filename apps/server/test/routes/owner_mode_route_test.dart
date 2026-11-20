import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:server/http/maintenance_gate.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/owner/mode/index.dart' as mode_route;
import 'competition_route_harness.dart';

final class _Seats implements OwnerNotices {
  const _Seats();

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(kAdminId));

  @override
  Future<Result<bool>> isOwner(UserId user) async =>
      Result.ok(user == const UserId(kAdminId));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Store implements AppModeStore {
  AppModeState state = AppModeState(
    mode: AppMode.normal,
    changedAt: DateTime.utc(2026, 11, 20),
  );

  @override
  Future<Result<AppModeState>> read() async => Result.ok(state);

  @override
  Future<Result<void>> set({
    required AppMode mode,
    required String reason,
    required UserId by,
  }) async {
    state = AppModeState(
      mode: mode,
      reason: reason,
      changedBy: by,
      changedAt: DateTime.utc(2026, 11, 20, 12),
    );
    return const Result.ok(null);
  }
}

// NK292_12
/// Script 292: `/owner/mode` through the real use-case; a change is seen
/// by this server's gate at once.
void main() {
  late _Store store;
  late AppModeCache cache;
  late CompositionRoot root;

  setUp(() {
    store = _Store();
    cache = AppModeCache(store);
    root = CompositionRoot.forTesting(
      ownerAppMode: OwnerAppMode(store: store, owners: const _Seats()),
      appModeCache: cache,
    );
  });

  Future<Map<String, Object?>> put(Object body) async => decodeBody(
    await mode_route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.put,
        body: body,
      ),
    ),
  );

  test('the owner closes the app; the gate sees it at once', () async {
    expect(await cache.current(), AppMode.normal);

    final Map<String, Object?> body = await put(const {
      'mode': 'closed',
      'reason': 'خطأ في النقاط',
    });

    expect(body['mode'], 'closed');
    expect(body['changed_by'], 'you');
    expect(body['reason'], 'خطأ في النقاط');
    expect(await cache.current(), AppMode.closed);
  });

  test('an unknown mode or no reason changes nothing', () async {
    expect(
      (await put(const {'mode': 'off', 'reason': 'x'}))['code'],
      'owner.mode_unknown',
    );
    expect(
      (await put(const {'mode': 'closed'}))['code'],
      'owner.reason_required',
    );
    expect(store.state.mode, AppMode.normal);
  });

  test('the owner reads it; another admin is refused', () async {
    final read = await decodeBody(
      await mode_route.onRequest(
        wireContext(
          root: root,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      ),
    );
    final refused = await mode_route.onRequest(
      wireContext(
        root: root,
        principal: const AuthenticatedUser(
          userId: UserId('0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b'),
          role: PlatformRole.admin,
        ),
        method: HttpMethod.put,
        body: const {'mode': 'closed', 'reason': 'x'},
      ),
    );

    expect(read['mode'], 'normal');
    expect(read['changed_by'], isNull);
    expect(refused.statusCode, HttpStatus.conflict);
    expect(store.state.mode, AppMode.normal);
  });
}
