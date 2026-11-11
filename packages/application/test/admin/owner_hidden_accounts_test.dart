import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _owner = '0a0a0a0a-0a0a-4a0a-8a0a-0a0a0a0a0a0a';
const _otherAdmin = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';
const _player = '0c0c0c0c-0c0c-4c0c-8c0c-0c0c0c0c0c0c';
const _reviewer = '0d0d0d0d-0d0d-4d0d-8d0d-0d0d0d0d0d0d';

final class _Owner implements OwnerNotices {
  const _Owner(this.id, {this.fails = false});

  final UserId? id;
  final bool fails;

  @override
  Future<Result<UserId?>> ownerId() async => fails
      ? const Result.err(AppError.transient('db.down', 'down'))
      : Result.ok(id);

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

/// The accounts in memory: [known] exist, [hidden] are hidden.
final class _Store implements HiddenAccountStore {
  final Set<String> known = <String>{_owner, _player, _reviewer};
  final Map<String, DateTime> hidden = <String, DateTime>{};
  int writes = 0;
  int reads = 0;

  @override
  Future<Result<List<HiddenAccount>>> list() async {
    reads++;
    return Result.ok(<HiddenAccount>[
      for (final MapEntry<String, DateTime> e in hidden.entries)
        HiddenAccount(
          user: User(
            id: UserId(e.key),
            email: 'r@t.io',
            displayName: 'مراجع التطبيق',
            role: PlatformRole.user,
            status: UserStatus.active,
          ),
          hiddenAt: e.value,
        ),
    ]);
  }

  @override
  Future<Result<bool>> hide(UserId target) async {
    writes++;
    if (!known.contains(target.value)) return const Result.ok(false);
    hidden.putIfAbsent(target.value, () => DateTime.utc(2026, 11, 11, 20));
    return const Result.ok(true);
  }

  @override
  Future<Result<bool>> show(UserId target) async {
    writes++;
    if (!known.contains(target.value)) return const Result.ok(false);
    hidden.remove(target.value);
    return const Result.ok(true);
  }
}

AuthenticatedUser _admin(String id) =>
    AuthenticatedUser(userId: UserId(id), role: PlatformRole.admin);

/// Script 258: the owner admin alone hides an account, shows it again and
/// lists them; every other caller is refused before anything is read or
/// written.
void main() {
  late _Store store;

  OwnerHiddenAccounts useCase({_Owner owner = const _Owner(UserId(_owner))}) {
    store = _Store();
    return OwnerHiddenAccounts(store: store, owner: owner);
  }

  test('the owner hides an account, lists it and shows it again', () async {
    final OwnerHiddenAccounts accounts = useCase();

    final Result<void> hidden = await accounts.hide(
      principal: _admin(_owner),
      targetUserId: _reviewer,
    );
    expect(hidden, isA<Ok<void>>());

    final Result<List<HiddenAccount>> listed = await accounts.list(
      principal: _admin(_owner),
    );
    final List<HiddenAccount> lines = (listed as Ok<List<HiddenAccount>>).value;
    expect(lines.single.user.id, const UserId(_reviewer));

    final Result<void> shown = await accounts.show(
      principal: _admin(_owner),
      targetUserId: _reviewer,
    );
    expect(shown, isA<Ok<void>>());
    expect(store.hidden, isEmpty);
  });

  test('another admin is refused and nothing is read or written', () async {
    final OwnerHiddenAccounts accounts = useCase();

    final Result<void> hidden = await accounts.hide(
      principal: _admin(_otherAdmin),
      targetUserId: _reviewer,
    );
    final Result<List<HiddenAccount>> listed = await accounts.list(
      principal: _admin(_otherAdmin),
    );

    expect((hidden as Err<void>).error.code, 'admin.owner_only');
    expect((listed as Err<List<HiddenAccount>>).error.code, 'admin.owner_only');
    expect(store.writes, 0);
    expect(store.reads, 0);
  });

  test('a player is refused by the role gate', () async {
    final OwnerHiddenAccounts accounts = useCase();

    final Result<void> hidden = await accounts.hide(
      principal: const AuthenticatedUser(
        userId: UserId(_player),
        role: PlatformRole.user,
      ),
      targetUserId: _reviewer,
    );

    expect((hidden as Err<void>).error.kind, ErrorKind.authorization);
    expect(store.writes, 0);
  });

  test('no owner found, or a failed lookup, refuses', () async {
    for (final _Owner owner in <_Owner>[
      const _Owner(null),
      const _Owner(UserId(_owner), fails: true),
    ]) {
      final OwnerHiddenAccounts accounts = useCase(owner: owner);

      final Result<void> hidden = await accounts.hide(
        principal: _admin(_owner),
        targetUserId: _reviewer,
      );

      expect((hidden as Err<void>).error.code, 'admin.owner_only');
      expect(store.writes, 0);
    }
  });

  test('the owner never hides himself', () async {
    final OwnerHiddenAccounts accounts = useCase();

    final Result<void> hidden = await accounts.hide(
      principal: _admin(_owner),
      targetUserId: _owner,
    );

    expect((hidden as Err<void>).error.code, 'admin.cannot_hide_owner');
    expect(store.writes, 0);
  });

  test('an unknown account, or a malformed id, is refused', () async {
    final OwnerHiddenAccounts accounts = useCase();

    final Result<void> unknown = await accounts.hide(
      principal: _admin(_owner),
      targetUserId: _otherAdmin,
    );
    final Result<void> malformed = await accounts.hide(
      principal: _admin(_owner),
      targetUserId: 'not-a-uuid',
    );

    expect((unknown as Err<void>).error.code, 'admin.user_not_found');
    expect(malformed, isA<Err<void>>());
    expect(store.hidden, isEmpty);
  });
}
