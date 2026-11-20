import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/owner/admins/[id]/index.dart' as act_route;
// ignore: always_use_package_imports
import '../../routes/owner/admins/index.dart' as list_route;
import 'competition_route_harness.dart';

const _admin = '0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b';

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

final class _Roster implements AdminRoster {
  final Map<String, bool> isAdmin = {kAdminId: true, _admin: true};
  final List<String> log = [];

  @override
  Future<Result<List<AdminMember>>> admins() async => Result.ok([
    for (final MapEntry<String, bool> e in isAdmin.entries)
      if (e.value)
        AdminMember(id: UserId(e.key), displayName: 'n', active: true),
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
  Future<Result<int>> endSessions(UserId user) async => const Result.ok(1);

  @override
  Future<Result<void>> record({
    required UserId user,
    required String action,
    required String reason,
    required UserId by,
    int? sessionsEnded,
  }) async {
    log.add(action);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<RoleChange>>> changes({int limit = 30}) async =>
      Result.ok([
        RoleChange(
          userName: 'خالد',
          action: 'revoke',
          reason: 'سوء استخدام',
          at: DateTime.utc(2026, 11, 20, 12),
          sessionsEnded: 1,
        ),
      ]);
}

// NK294_15
/// Script 294: `/owner/admins` through the real use-case.
void main() {
  late _Roster roster;
  late CompositionRoot root;

  setUp(() {
    roster = _Roster();
    root = CompositionRoot.forTesting(
      ownerAdmins: OwnerAdmins(roster: roster, owners: const _Seats()),
    );
  });

  Future<Map<String, Object?>> act(String id, Object body) async => decodeBody(
    await act_route.onRequest(
      wireContext(root: root, principal: adminPrincipal(), body: body),
      id,
    ),
  );

  test('the owner lists the admins, the seats marked, and the log', () async {
    final body = await decodeBody(
      await list_route.onRequest(
        wireContext(
          root: root,
          principal: adminPrincipal(),
          method: HttpMethod.get,
        ),
      ),
    );

    final admins = (body['admins']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    expect(admins.where((a) => a['is_owner'] == true), hasLength(1));
    final change =
        (body['changes']! as List<Object?>).single! as Map<Object?, Object?>;
    expect(change['reason'], 'سوء استخدام');
  });

  test('the owner revokes an admin; the sessions end with it', () async {
    final body = await act(_admin, const {
      'action': 'revoke',
      'reason': 'سوء استخدام',
    });

    expect(body, {'action': 'revoke', 'sessions_ended': 1});
    expect(roster.isAdmin[_admin], isFalse);
    expect(roster.log, ['revoke']);
  });

  test('an owner seat is never revoked; a reason is required', () async {
    final owner = await act(kAdminId, const {
      'action': 'revoke',
      'reason': 'x',
    });
    final blank = await act(_admin, const {'action': 'revoke'});

    expect(owner['code'], 'owner.cannot_revoke_owner');
    expect(blank['code'], 'owner.reason_required');
    expect(roster.isAdmin[kAdminId], isTrue);
    expect(roster.log, isEmpty);
  });

  test('another admin is refused', () async {
    final response = await act_route.onRequest(
      wireContext(
        root: root,
        principal: const AuthenticatedUser(
          userId: UserId(_admin),
          role: PlatformRole.admin,
        ),
        body: const {'action': 'revoke', 'reason': 'x'},
      ),
      kAdminId,
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect(roster.log, isEmpty);
  });
}
