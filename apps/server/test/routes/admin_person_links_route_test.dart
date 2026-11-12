import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/admin/person-links/[id]/index.dart' as person_link;
// ignore: always_use_package_imports
import '../../routes/admin/person-links/index.dart' as person_links;
import 'competition_route_harness.dart';

const _otherAdmin = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';
const _second = 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1';
const _other = 'd2d2d2d2-d2d2-4d2d-8d2d-d2d2d2d2d2d2';

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

final class _Store implements PersonLinkStore {
  PersonLinkRefusal? refusal;
  final List<(UserId, UserId?, List<UserId>)> sets =
      <(UserId, UserId?, List<UserId>)>[];
  final List<UserId> unlinked = <UserId>[];

  @override
  Future<Result<List<LinkedPerson>>> list() async => Result.ok(<LinkedPerson>[
    LinkedPerson(
      main: const UserId(kTargetUserId),
      accounts: <LinkedAccount>[
        LinkedAccount(user: storedUser(), counted: true, hidden: false),
        LinkedAccount(
          user: storedUser(id: _other, email: 'o@t.io'),
          counted: false,
          hidden: true,
        ),
      ],
    ),
  ]);

  @override
  Future<Result<PersonLinkRefusal?>> set({
    required UserId main,
    required UserId? second,
    required List<UserId> others,
    required UserId by,
  }) async {
    sets.add((main, second, others));
    return Result.ok(refusal);
  }

  @override
  Future<Result<int>> unlink(UserId main) async {
    unlinked.add(main);
    return const Result.ok(2);
  }
}

/// Script 263: one person's accounts, linked by the owner admin alone,
/// through the real wiring.
void main() {
  late _Store store;

  CompositionRoot root({bool wired = true}) {
    store = _Store();
    return CompositionRoot.forTesting(
      ownerPersonLinks: wired
          ? OwnerPersonLinks(store: store, owner: const _Owner())
          : null,
    );
  }

  AuthenticatedUser otherAdmin() => const AuthenticatedUser(
    userId: UserId(_otherAdmin),
    role: PlatformRole.admin,
  );

  test('the owner lists the people, the main account first', () async {
    final response = await person_links.onRequest(
      wireContext(
        root: root(),
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    final person =
        ((await decodeBody(response))['people']! as List<Object?>).single!
            as Map;
    expect(person['main_id'], kTargetUserId);
    final accounts = (person['accounts']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    expect(accounts.first['counted'], isTrue);
    expect(accounts.last['hidden'], isTrue);
    expect((accounts.last['user']! as Map)['id'], _other);
  });

  test('the owner sets a person', () async {
    final r = root();

    final response = await person_link.onRequest(
      wireContext(
        root: r,
        principal: adminPrincipal(),
        method: HttpMethod.put,
        body: const {
          'second_id': _second,
          'other_ids': [_other],
        },
      ),
      kTargetUserId,
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(await decodeBody(response), {'set': true});
    final (main, second, others) = store.sets.single;
    expect(main, const UserId(kTargetUserId));
    expect(second, const UserId(_second));
    expect(others, <UserId>[const UserId(_other)]);
  });

  test('an account linked elsewhere is a 409', () async {
    final r = root();
    store.refusal = PersonLinkRefusal.taken;

    final response = await person_link.onRequest(
      wireContext(
        root: r,
        principal: adminPrincipal(),
        method: HttpMethod.put,
        body: const {
          'other_ids': [_other],
        },
      ),
      kTargetUserId,
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect((await decodeBody(response))['code'], 'admin.person_account_taken');
  });

  test('the owner unlinks', () async {
    final r = root();

    final response = await person_link.onRequest(
      wireContext(
        root: r,
        principal: adminPrincipal(),
        method: HttpMethod.delete,
      ),
      kTargetUserId,
    );

    expect(await decodeBody(response), {'unlinked': 2});
    expect(store.unlinked, <UserId>[const UserId(kTargetUserId)]);
  });

  test('another admin is refused, nothing written', () async {
    final r = root();

    final response = await person_link.onRequest(
      wireContext(
        root: r,
        principal: otherAdmin(),
        method: HttpMethod.put,
        body: const {
          'other_ids': [_other],
        },
      ),
      kTargetUserId,
    );

    expect((await decodeBody(response))['code'], 'admin.owner_only');
    expect(store.sets, isEmpty);
  });

  test('a player is refused', () async {
    final response = await person_links.onRequest(
      wireContext(
        root: root(),
        principal: userPrincipal(),
        method: HttpMethod.get,
      ),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('an unwired root is 503; other methods 405', () async {
    final unwired = await person_links.onRequest(
      wireContext(
        root: root(wired: false),
        principal: adminPrincipal(),
        method: HttpMethod.get,
      ),
    );
    final post = await person_link.onRequest(
      wireContext(root: root(), principal: adminPrincipal()),
      kTargetUserId,
    );

    expect(unwired.statusCode, HttpStatus.serviceUnavailable);
    expect(post.statusCode, HttpStatus.methodNotAllowed);
  });
}
