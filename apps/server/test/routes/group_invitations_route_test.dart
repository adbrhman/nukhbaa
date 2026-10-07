import 'dart:io';

import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:server/composition/composition_root.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

// dart_frog routes have no `package:` URI (they live outside `lib/`); a
// relative import is the documented way to unit-test the handler in isolation.
// ignore: always_use_package_imports
import '../../routes/groups/[id]/invitations/index.dart' as invite_route;
// ignore: always_use_package_imports
import '../../routes/groups/invitations/[invitationId]/accept/index.dart'
    as accept_route;
// ignore: always_use_package_imports
import '../../routes/groups/invitations/[invitationId]/decline/index.dart'
    as decline_route;
// ignore: always_use_package_imports
import '../../routes/groups/invitations/index.dart' as list_route;
import 'competition_route_harness.dart';

const _invitationId = 'd1d1d1d1-d1d1-d1d1-d1d1-d1d1d1d1d1d1';

/// The invitations of the run, as the Postgres table keeps them: one per
/// (league, player).
final class _Invitations implements GroupInvitationRepository {
  final List<GroupInvitation> rows = <GroupInvitation>[];

  @override
  Future<Result<bool>> createIfAbsent({
    required String id,
    required GroupId groupId,
    required UserId inviter,
    required UserId invitee,
    required DateTime createdAt,
  }) async {
    if (rows.any((r) => r.groupId == groupId && r.inviteeUserId == invitee)) {
      return const Result.ok(false);
    }
    rows.add(
      GroupInvitation(
        id: id,
        groupId: groupId,
        groupName: 'The Circle',
        inviterUserId: inviter,
        inviterName: 'Member',
        inviteeUserId: invitee,
        status: GroupInvitationStatus.pending,
        createdAt: createdAt,
      ),
    );
    return const Result.ok(true);
  }

  @override
  Future<Result<GroupInvitation?>> findForInvitee({
    required String id,
    required UserId invitee,
  }) async {
    for (final GroupInvitation r in rows) {
      if (r.id == id && r.inviteeUserId == invitee) return Result.ok(r);
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> respond({
    required String id,
    required UserId invitee,
    required GroupInvitationStatus status,
    required DateTime at,
  }) async {
    final int i = rows.indexWhere(
      (r) =>
          r.id == id &&
          r.inviteeUserId == invitee &&
          r.status == GroupInvitationStatus.pending,
    );
    if (i < 0) return const Result.ok(false);
    final GroupInvitation r = rows[i];
    rows[i] = GroupInvitation(
      id: r.id,
      groupId: r.groupId,
      groupName: r.groupName,
      inviterUserId: r.inviterUserId,
      inviterName: r.inviterName,
      inviteeUserId: r.inviteeUserId,
      status: status,
      createdAt: r.createdAt,
    );
    return const Result.ok(true);
  }

  @override
  Future<Result<List<GroupInvitation>>> listForInvitee(
    UserId invitee, {
    required int limit,
  }) async => Result.ok([
    for (final GroupInvitation r in rows)
      if (r.inviteeUserId == invitee) r,
  ]);

  @override
  Future<Result<GroupInviteePush>> pushTargetOf(UserId user) async =>
      const Result.ok(GroupInviteePush(tokens: <String>['tok-1']));
}

final class _Sender implements PushSender {
  final List<String?> links = <String?>[];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    links.add(link);
    return const Result.ok(<String>[]);
  }
}

AuthenticatedUser _invitee() => const AuthenticatedUser(
  userId: UserId(kTargetUserId),
  role: PlatformRole.user,
);

/// The invitation routes through the real wiring: a member invites a
/// player, who is told in the inbox and by push, lists the invitation and
/// accepts it (and is then in the league) or declines it.
void main() {
  late InMemoryGroupRepository groups;
  late InMemoryNotificationRepository notifications;
  late _Invitations invitations;
  late _Sender sender;
  late CompositionRoot root;

  setUp(() {
    groups = InMemoryGroupRepository()
      ..seedGroup(storedGroup())
      ..seedMembership(
        storedMembership(id: kMemberMembershipId, userId: kUserId),
      );
    notifications = InMemoryNotificationRepository();
    invitations = _Invitations();
    sender = _Sender();
    final Clock clock = FixedClock(DateTime.utc(2026, 10, 7, 12));
    final IdGenerator ids = ScriptedIdGenerator([
      _invitationId,
      'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1',
      'f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1',
    ]);
    root = CompositionRoot.forTesting(
      inviteToGroup: InviteToGroup(
        groups: groups,
        invitations: invitations,
        notify: CreateNotification(
          notifications: notifications,
          idGenerator: ids,
          clock: clock,
        ),
        sender: sender,
        idGenerator: ids,
        clock: clock,
      ),
      respondToGroupInvitation: RespondToGroupInvitation(
        invitations: invitations,
        groups: groups,
        join: JoinGroupByInvite(
          repository: groups,
          idGenerator: ids,
          clock: clock,
        ),
        clock: clock,
      ),
      listMyGroupInvitations: ListMyGroupInvitations(invitations: invitations),
    );
  });

  Future<Response> invite(AuthenticatedUser who) => invite_route.onRequest(
    wireContext(
      root: root,
      principal: who,
      body: const {'user_id': kTargetUserId},
    ),
    kGroupId,
  );

  test(
    'a member invites: the player is told in the inbox and by push',
    () async {
      final response = await invite(userPrincipal());

      expect(response.statusCode, HttpStatus.ok);
      expect((await decodeBody(response))['invited'], isTrue);
      final Notification told = notifications.notifications.single;
      expect(told.recipientId.value, kTargetUserId);
      expect(told.kind, NotificationKind.groupInvited);
      expect(told.subject.groupId?.value, kGroupId);
      expect(told.subject.actorUserId?.value, kUserId);
      expect(sender.links, <String?>['inbox']);

      final again = await invite(userPrincipal());
      expect((await decodeBody(again))['invited'], isFalse);
      expect(notifications.notifications, hasLength(1));
      expect(sender.links, hasLength(1));
    },
  );

  test('someone outside the league cannot invite to it (401)', () async {
    final response = await invite(
      const AuthenticatedUser(
        userId: UserId(kNonMemberUserId),
        role: PlatformRole.user,
      ),
    );

    expect(response.statusCode, HttpStatus.unauthorized);
    expect((await decodeBody(response))['code'], 'group.not_a_member');
    expect(invitations.rows, isEmpty);
  });

  test('the player lists the invitation and accepts: in the league', () async {
    await invite(userPrincipal());

    final listed = await list_route.onRequest(
      wireContext(root: root, principal: _invitee(), method: HttpMethod.get),
    );
    final body = await decodeBody(listed);
    final invitation =
        (body['invitations']! as List<Object?>).single! as Map<String, Object?>;
    expect(invitation['id'], _invitationId);
    expect(invitation['group_name'], 'The Circle');
    expect(invitation['status'], 'pending');

    final accepted = await accept_route.onRequest(
      wireContext(root: root, principal: _invitee()),
      _invitationId,
    );
    expect(accepted.statusCode, HttpStatus.ok);
    expect((await decodeBody(accepted))['status'], 'accepted');
    final mine = await groups.findMembership(
      const GroupId(kGroupId),
      const UserId(kTargetUserId),
    );
    expect((mine as Ok<GroupMembership?>).value, isNotNull);
  });

  test(
    'the player declines: not in the league, and it stays declined',
    () async {
      await invite(userPrincipal());

      final declined = await decline_route.onRequest(
        wireContext(root: root, principal: _invitee()),
        _invitationId,
      );
      expect((await decodeBody(declined))['status'], 'declined');
      final again = await accept_route.onRequest(
        wireContext(root: root, principal: _invitee()),
        _invitationId,
      );
      expect((await decodeBody(again))['status'], 'declined');
      final mine = await groups.findMembership(
        const GroupId(kGroupId),
        const UserId(kTargetUserId),
      );
      expect((mine as Ok<GroupMembership?>).value, isNull);
    },
  );

  test("someone else's invitation is not found (409)", () async {
    await invite(userPrincipal());

    final response = await accept_route.onRequest(
      wireContext(root: root, principal: userPrincipal()),
      _invitationId,
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect((await decodeBody(response))['code'], 'group.invitation_not_found');
  });
}
