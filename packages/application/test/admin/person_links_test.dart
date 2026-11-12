import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

/// Script 263: one person behind several accounts -- the close-name hint
/// in the new-player push and list, and the owner's links.

const String _owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const String _a = '11111111-1111-4111-8111-111111111111';
const String _b = '22222222-2222-4222-8222-222222222222';
const String _c = '33333333-3333-4333-8333-333333333333';
const String _d = '44444444-4444-4444-8444-444444444444';

const AuthenticatedUser _ownerUser = AuthenticatedUser(
  userId: UserId(_owner),
  role: PlatformRole.admin,
);
const AuthenticatedUser _otherAdmin = AuthenticatedUser(
  userId: UserId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  role: PlatformRole.admin,
);
const AuthenticatedUser _player = AuthenticatedUser(
  userId: UserId(_a),
  role: PlatformRole.user,
);

const List<AccountName> _names = <AccountName>[
  AccountName(
    id: UserId(_a),
    displayName: 'عبدالرحمن المغربي',
    email: 'a@t.io',
  ),
  AccountName(
    id: UserId(_b),
    displayName: 'عبد الرحمن محمد المغربي',
    email: 'b@t.io',
  ),
  AccountName(id: UserId(_c), displayName: 'عبدالله المغربي', email: 'c@t.io'),
  AccountName(
    id: UserId(_d),
    displayName: 'عبدُالرحمن المغربى',
    email: 'd@t.io',
  ),
];

final class _Names implements AccountNameDirectory {
  _Names({this.fails = false});

  final bool fails;
  int reads = 0;

  @override
  Future<Result<List<AccountName>>> all() async {
    reads++;
    return fails
        ? const Result.err(AppError.transient('db.down', 'down'))
        : const Result.ok(_names);
  }
}

final class _Owner implements OwnerNotices {
  const _Owner();

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

final class _Store implements PersonLinkStore {
  PersonLinkRefusal? refusal;
  final List<(UserId, UserId?, List<UserId>, UserId)> sets =
      <(UserId, UserId?, List<UserId>, UserId)>[];
  final List<UserId> unlinked = <UserId>[];

  @override
  Future<Result<List<LinkedPerson>>> list() async =>
      const Result.ok(<LinkedPerson>[
        LinkedPerson(
          main: UserId(_a),
          accounts: <LinkedAccount>[
            LinkedAccount(
              user: User(
                id: UserId(_a),
                email: 'a@t.io',
                role: PlatformRole.user,
                status: UserStatus.active,
                displayName: 'عبدالرحمن المغربي',
              ),
              counted: true,
              hidden: false,
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
    sets.add((main, second, others, by));
    return Result.ok(refusal);
  }

  @override
  Future<Result<int>> unlink(UserId main) async {
    unlinked.add(main);
    return const Result.ok(3);
  }
}

final class _Targets implements AdminPushTargetReader {
  @override
  Future<Result<List<String>>> tokensForActiveAdmins() async =>
      const Result.ok(<String>['t1']);
}

final class _Sender implements PushSender {
  final List<String> bodies = <String>[];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    bodies.add(body);
    return const Result.ok(<String>[]);
  }
}

final class _Reader implements NewPlayerReader {
  @override
  Future<Result<List<NewPlayer>>> newPlayers({
    required int days,
    required int limit,
  }) async => Result.ok(<NewPlayer>[
    NewPlayer(
      user: const User(
        id: UserId(_d),
        email: 'd@t.io',
        role: PlatformRole.user,
        status: UserStatus.active,
        displayName: 'عبدُالرحمن المغربى',
      ),
      joinedAt: DateTime.utc(2026, 11, 12),
      phoneAccounts: 1,
      predictions: 0,
      nameHint: null,
    ),
  ]);
}

void main() {
  group('accountsLike', () {
    test('finds the same first and last name under other spellings', () {
      expect(
        [
          for (final a in accountsLike(
            _names,
            name: 'عبد الرحمن المغربي',
            exceptEmail: 'D@t.io',
          ))
            a.id.value,
        ],
        [_a, _b],
      );
    });

    test('leaves the account itself out, and keeps to the limit', () {
      expect(
        accountsLike(
          _names,
          name: 'عبدالرحمن المغربي',
          except: const UserId(_a),
          limit: 1,
        ).single.id.value,
        _b,
      );
    });

    test('a one-part name has nothing like it', () {
      expect(accountsLike(_names, name: 'عبدالرحمن'), isEmpty);
    });
  });

  group('the new-player push', () {
    test('names the accounts like the new one', () async {
      final sender = _Sender();

      await NotifyNewUserRegistered(
        targets: _Targets(),
        sender: sender,
        names: _Names(),
      )(displayName: 'عبدُالرحمن المغربى', email: 'd@t.io');

      expect(
        sender.bodies.single,
        '«عبدُالرحمن المغربى» · d@t.io · يشبه: «عبدالرحمن المغربي»، '
        '«عبد الرحمن محمد المغربي»',
      );
    });

    test('a failed read of the names still sends the push', () async {
      final sender = _Sender();

      await NotifyNewUserRegistered(
        targets: _Targets(),
        sender: sender,
        names: _Names(fails: true),
      )(displayName: 'عبدالله المغربي', email: 'x@t.io');

      expect(sender.bodies.single, '«عبدالله المغربي» · x@t.io');
    });
  });

  group('the new players', () {
    test('each carries the names like his', () async {
      final result = await AdminListNewPlayers(
        players: _Reader(),
        names: _Names(),
      )(principal: _ownerUser);

      expect((result as Ok<List<NewPlayer>>).value.single.similarTo, <String>[
        'عبدالرحمن المغربي',
        'عبد الرحمن محمد المغربي',
      ]);
    });

    test('a failed read of the names keeps the list', () async {
      final result = await AdminListNewPlayers(
        players: _Reader(),
        names: _Names(fails: true),
      )(principal: _ownerUser);

      expect((result as Ok<List<NewPlayer>>).value.single.similarTo, isEmpty);
    });
  });

  group('OwnerPersonLinks', () {
    test('the owner sets a person: main, second, the others hidden', () async {
      final store = _Store();

      final result = await OwnerPersonLinks(store: store, owner: const _Owner())
          .set(
            principal: _ownerUser,
            mainId: _a,
            secondId: _b,
            otherIds: <String>[_d],
          );

      expect(result, isA<Ok<void>>());
      final (main, second, others, by) = store.sets.single;
      expect(main, const UserId(_a));
      expect(second, const UserId(_b));
      expect(others, <UserId>[const UserId(_d)]);
      expect(by, const UserId(_owner));
    });

    test('no second account is fine', () async {
      final store = _Store();

      await OwnerPersonLinks(store: store, owner: const _Owner()).set(
        principal: _ownerUser,
        mainId: _a,
        secondId: null,
        otherIds: <String>[_b, _d],
      );

      expect(store.sets.single.$2, isNull);
    });

    test('another admin and a player are refused, nothing written', () async {
      final store = _Store();
      final links = OwnerPersonLinks(store: store, owner: const _Owner());

      final other = await links.set(
        principal: _otherAdmin,
        mainId: _a,
        secondId: null,
        otherIds: <String>[_b],
      );
      final player = await links.list(principal: _player);

      expect((other as Err<void>).error.code, 'admin.owner_only');
      expect(
        (player as Err<List<LinkedPerson>>).error.code,
        'auth.insufficient_role',
      );
      expect(store.sets, isEmpty);
    });

    test("the owner's own account is never hidden by a link", () async {
      final store = _Store();

      final result = await OwnerPersonLinks(store: store, owner: const _Owner())
          .set(
            principal: _ownerUser,
            mainId: _a,
            secondId: null,
            otherIds: <String>[_owner],
          );

      expect((result as Err<void>).error.code, 'admin.cannot_hide_owner');
      expect(store.sets, isEmpty);
    });

    for (final (refusal, code) in <(PersonLinkRefusal, String)>[
      (PersonLinkRefusal.tooFew, 'admin.person_too_few'),
      (PersonLinkRefusal.duplicate, 'admin.person_duplicate'),
      (PersonLinkRefusal.unknown, 'admin.user_not_found'),
      (PersonLinkRefusal.taken, 'admin.person_account_taken'),
    ]) {
      test('the store refusing ${refusal.name} is $code', () async {
        final store = _Store()..refusal = refusal;

        final result =
            await OwnerPersonLinks(store: store, owner: const _Owner()).set(
              principal: _ownerUser,
              mainId: _a,
              secondId: null,
              otherIds: <String>[_b],
            );

        expect((result as Err<void>).error.code, code);
      });
    }

    test('a malformed id is refused before the store', () async {
      final store = _Store();

      final result = await OwnerPersonLinks(store: store, owner: const _Owner())
          .set(
            principal: _ownerUser,
            mainId: _a,
            secondId: null,
            otherIds: <String>['nope'],
          );

      expect(result, isA<Err<void>>());
      expect(store.sets, isEmpty);
    });

    test('the owner lists and unlinks', () async {
      final store = _Store();
      final links = OwnerPersonLinks(store: store, owner: const _Owner());

      final listed = await links.list(principal: _ownerUser);
      final unlinked = await links.unlink(principal: _ownerUser, mainId: _a);

      expect((listed as Ok<List<LinkedPerson>>).value.single.main.value, _a);
      expect((unlinked as Ok<int>).value, 3);
      expect(store.unlinked, <UserId>[const UserId(_a)]);
    });
  });
}
