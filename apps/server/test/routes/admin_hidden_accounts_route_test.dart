import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/hidden-accounts/[id]/index.dart' as hidden_account;
// ignore: always_use_package_imports
import '../../routes/admin/hidden-accounts/index.dart' as hidden_accounts;
import 'competition_route_harness.dart';

const _otherAdmin = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';

final class _Owner implements OwnerNotices {
  const _Owner();

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(kAdminId));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Store implements HiddenAccountStore {
  final Map<String, DateTime> hidden = <String, DateTime>{};

  @override
  Future<Result<List<HiddenAccount>>> list() async => Result.ok(<HiddenAccount>[
    for (final MapEntry<String, DateTime> e in hidden.entries)
      HiddenAccount(
        user: storedUser(id: e.key),
        hiddenAt: e.value,
      ),
  ]);

  @override
  Future<Result<bool>> hide(UserId target) async {
    if (target.value != kTargetUserId) return const Result.ok(false);
    hidden.putIfAbsent(target.value, () => DateTime.utc(2026, 11, 11, 20));
    return const Result.ok(true);
  }

  @override
  Future<Result<bool>> show(UserId target) async {
    if (target.value != kTargetUserId) return const Result.ok(false);
    hidden.remove(target.value);
    return const Result.ok(true);
  }
}

/// Script 258: the owner admin's hidden accounts through the real wiring;
/// any other admin or a player is refused before the store is touched.
void main() {
  late _Store store;

  CompositionRoot root({bool wired = true}) {
    store = _Store();
    return CompositionRoot.forTesting(
      ownerHiddenAccounts: wired
          ? OwnerHiddenAccounts(store: store, owner: const _Owner())
          : null,
    );
  }

  Future<Response> send(
    AuthenticatedUser principal,
    HttpMethod method, {
    String id = kTargetUserId,
    bool wired = true,
  }) => hidden_account.onRequest(
    wireContext(
      root: root(wired: wired),
      principal: principal,
      method: method,
    ),
    id,
  );

  test('the owner hides an account, then reads it in the list', () async {
    final CompositionRoot wiredRoot = root();

    final Response hidden = await hidden_account.onRequest(
      wireContext(
        root: wiredRoot,
        principal: adminPrincipal(),
        method: HttpMethod.post,
      ),
      kTargetUserId,
    );
    expect(hidden.statusCode, HttpStatus.ok);
    expect((await decodeBody(hidden))['hidden'], isTrue);

    final Response listed = await hidden_accounts.onRequest(
      wireContext(
        root: wiredRoot,
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );
    expect(listed.statusCode, HttpStatus.ok);
    final Map<String, Object?> body = await decodeBody(listed);
    final Map<String, Object?> line =
        ((body['accounts']! as List<Object?>).single! as Map)
            .cast<String, Object?>();
    expect((line['user']! as Map)['id'], kTargetUserId);
    expect(line['hidden_at'], '2026-11-11T20:00:00.000Z');
  });

  test('the owner shows it again', () async {
    final Response shown = await send(adminPrincipal(), HttpMethod.delete);

    expect(shown.statusCode, HttpStatus.ok);
    expect((await decodeBody(shown))['hidden'], isFalse);
  });

  test('another admin is refused and nothing is written', () async {
    final Response refused = await send(
      const AuthenticatedUser(
        userId: UserId(_otherAdmin),
        role: PlatformRole.admin,
      ),
      HttpMethod.post,
    );

    expect(refused.statusCode, HttpStatus.conflict);
    expect((await decodeBody(refused))['code'], 'admin.owner_only');
    expect(store.hidden, isEmpty);
  });

  test('a player is refused and nothing is written', () async {
    final Response refused = await send(userPrincipal(), HttpMethod.post);

    expect(refused.statusCode, HttpStatus.unauthorized);
    expect(store.hidden, isEmpty);
  });

  test('the owner never hides himself', () async {
    final Response refused = await send(
      adminPrincipal(),
      HttpMethod.post,
      id: kAdminId,
    );

    expect(refused.statusCode, HttpStatus.conflict);
    expect((await decodeBody(refused))['code'], 'admin.cannot_hide_owner');
  });

  test('another method is 405, an unwired root is 503', () async {
    final Response put = await send(adminPrincipal(), HttpMethod.put);
    final Response unwired = await send(
      adminPrincipal(),
      HttpMethod.post,
      wired: false,
    );

    expect(put.statusCode, HttpStatus.methodNotAllowed);
    expect(unwired.statusCode, HttpStatus.serviceUnavailable);
  });
}
