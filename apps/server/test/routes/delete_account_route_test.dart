import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/me/account/index.dart' as route;
import 'competition_route_harness.dart';

/// In-memory stand-in for `identity.delete_account` (migration 0178).
final class _Accounts implements AccountDeletion {
  final List<String> anonymised = <String>[];

  @override
  Future<Result<bool>> anonymise(UserId userId) async {
    anonymised.add(userId.value);
    return const Result.ok(true);
  }
}

// Audit M-05 (script 113): a player deletes his own account, through the
// real route and the real DeleteMyAccount.
void main() {
  late _Accounts accounts;
  late CompositionRoot root;

  setUp(() {
    accounts = _Accounts();
    root = CompositionRoot.forTesting(
      deleteMyAccount: DeleteMyAccount(accounts: accounts),
    );
  });

  test('DELETE deletes the caller, and only the caller', () async {
    final response = await route.onRequest(
      wireContext(
        root: root,
        principal: userPrincipal(),
        method: HttpMethod.delete,
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect((await decodeBody(response))['deleted'], isTrue);
    expect(accounts.anonymised, <String>[kUserId]);
  });

  test('an admin account is kept', () async {
    final response = await route.onRequest(
      wireContext(
        root: root,
        principal: adminPrincipal(),
        method: HttpMethod.delete,
      ),
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect(accounts.anonymised, isEmpty);
  });

  test('only DELETE is allowed', () async {
    final response = await route.onRequest(
      wireContext(root: root, principal: userPrincipal()),
    );

    expect(response.statusCode, HttpStatus.methodNotAllowed);
    expect(accounts.anonymised, isEmpty);
  });

  test('unwired, the route answers 503 and deletes nothing', () async {
    final response = await route.onRequest(
      wireContext(
        root: CompositionRoot.forTesting(),
        principal: userPrincipal(),
        method: HttpMethod.delete,
      ),
    );

    expect(response.statusCode, HttpStatus.serviceUnavailable);
    expect(accounts.anonymised, isEmpty);
  });
}
