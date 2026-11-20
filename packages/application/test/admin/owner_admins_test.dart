import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

const _owner = '00000000-0000-4000-8294-0000000000aa';
const _backup = '00000000-0000-4000-8294-0000000000ab';
const _admin = '00000000-0000-4000-8294-0000000000bb';
const _player = '00000000-0000-4000-8294-0000000000cc';

/// The seats: [_owner] and [_backup]; [fails] breaks every lookup.
final class _Seats implements OwnerNotices {
  bool fails = false;

  @override
  Future<Result<UserId?>> ownerId() async => const Result.ok(UserId(_owner));

  @override
  Future<Result<bool>> isOwner(UserId user) async => fails
      ? const Result.err(AppError.transient('db.down', 'down'))
      : Result.ok(
          user == const UserId(_owner) || user == const UserId(_backup),
        );

  @override
  Future<Result<void>> tell({
    required String title,
    required String body,
  }) async => const Result.ok(null);
}

/// identity.users roles, sessions and the log, in memory.
final class _Roster implements AdminRoster {
  final Map<String, bool> isAdmin = {
    _owner: true,
    _backup: true,
    _admin: true,
    _player: false,
  };
  final Map<String, int> sessions = {_admin: 2, _player: 1};
  final List<String> log = [];

  @override
  Future<Result<List<AdminMember>>> admins() async => Result.ok([
    for (final MapEntry<String, bool> e in isAdmin.entries)
      if (e.value)
        AdminMember(id: UserId(e.key), displayName: e.key, active: true),
  ]);

  @override
  Future<Result<bool>> setRole({
    required UserId user,
    required bool admin,
  }) async {
    final bool? now = isAdmin[user.value];
    if (now == null || now == admin) return const Result.ok(false);
    isAdmin[user.value] = admin;
    return const Result.ok(true);
  }

  @override
  Future<Result<int>> endSessions(UserId user) async =>
      Result.ok(sessions.remove(user.value) ?? 0);

  @override
  Future<Result<void>> record({
    required UserId user,
    required String action,
    required String reason,
    required UserId by,
    int? sessionsEnded,
  }) async {
    log.add('$action|${user.value}|$reason|${by.value}|$sessionsEnded');
    return const Result.ok(null);
  }

  @override
  Future<Result<List<RoleChange>>> changes({int limit = 30}) async =>
      const Result.ok([]);
}

// NK294_11
/// Script 294: the owners' hand on the admins.
void main() {
  late _Roster roster;
  late _Seats seats;
  late OwnerAdmins admins;
  const AuthenticatedUser owner = AuthenticatedUser(
    userId: UserId(_owner),
    role: PlatformRole.admin,
  );

  setUp(() {
    roster = _Roster();
    seats = _Seats();
    admins = OwnerAdmins(roster: roster, owners: seats);
  });

  Future<Result<int>> act(
    String user,
    String action, {
    String? reason = 'سبب',
    AuthenticatedUser who = owner,
  }) =>
      admins.act(principal: who, userId: user, action: action, reason: reason);

  test('lists the admins, the seats marked', () async {
    final result = await admins.list(principal: owner);

    final AdminRosterView view = (result as Ok<AdminRosterView>).value;
    expect(view.admins, hasLength(3));
    expect(
      view.admins.where((s) => s.owner).map((s) => s.member.id.value),
      unorderedEquals([_owner, _backup]),
    );
  });

  test('promotes a player, once, and keeps why', () async {
    final first = await act(_player, 'promote');
    final again = await act(_player, 'promote');

    expect((first as Ok<int>).value, 0);
    expect(roster.isAdmin[_player], isTrue);
    expect((again as Err<int>).error.code, 'owner.not_a_player');
    expect(roster.log, ['promote|$_player|سبب|$_owner|null']);
  });

  test('revokes an admin and ends his sessions', () async {
    final result = await act(_admin, 'revoke');

    expect((result as Ok<int>).value, 2);
    expect(roster.isAdmin[_admin], isFalse);
    expect(roster.sessions.containsKey(_admin), isFalse);
    expect(roster.log.single, startsWith('revoke|$_admin|'));
  });

  test('never revokes an owner seat, his own included', () async {
    final backup = await act(_backup, 'revoke', who: owner);
    final self = await act(_owner, 'revoke');

    expect((backup as Err<int>).error.code, 'owner.cannot_revoke_owner');
    expect((self as Err<int>).error.code, 'owner.cannot_revoke_owner');
    expect(roster.isAdmin[_backup], isTrue);
    expect(roster.log, isEmpty);
  });

  test('ends a player\'s sessions without changing his role', () async {
    final result = await act(_player, 'end_sessions');

    expect((result as Ok<int>).value, 1);
    expect(roster.isAdmin[_player], isFalse);
  });

  test('no reason, an unknown action, another admin: nothing', () async {
    final blank = await act(_admin, 'revoke', reason: '  ');
    final unknown = await act(_admin, 'delete');
    final other = await act(
      _player,
      'promote',
      who: const AuthenticatedUser(
        userId: UserId(_admin),
        role: PlatformRole.admin,
      ),
    );
    seats.fails = true;
    final failed = await act(_player, 'promote');

    expect((blank as Err<int>).error.code, 'owner.reason_required');
    expect((unknown as Err<int>).error.code, 'owner.action_invalid');
    expect((other as Err<int>).error.code, 'admin.owner_only');
    expect((failed as Err<int>).error.code, 'admin.owner_only');
    expect(roster.isAdmin[_admin], isTrue);
    expect(roster.isAdmin[_player], isFalse);
    expect(roster.log, isEmpty);
  });
}
