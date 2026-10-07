import 'package:application/application.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import '../notification/fakes.dart' show InMemoryNotificationRepository;
import 'fakes.dart'
    show
        FakeClock,
        FakeIdGenerator,
        InMemoryGroupRepository,
        principalUser,
        storedGroup,
        storedMembership;

const _group = '11111111-1111-1111-1111-111111111111';
const _owner = '21111111-1111-1111-1111-111111111111';
const _friend = '22222222-1111-1111-1111-111111111111';
const _stranger = '23333333-1111-1111-1111-111111111111';
const _invitation = '31111111-1111-1111-1111-111111111111';

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
        inviterName: 'Owner',
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
  final List<String> titles = <String>[];
  final List<String?> links = <String?>[];

  @override
  Future<Result<List<String>>> send({
    required List<String> tokens,
    required String title,
    required String body,
    String? link,
  }) async {
    titles.add(title);
    links.add(link);
    return const Result.ok(<String>[]);
  }
}

void main() {
  late InMemoryGroupRepository groups;
  late InMemoryNotificationRepository notifications;
  late _Invitations invitations;
  late _Sender sender;

  InviteToGroup invite({DateTime? now}) {
    final FakeClock clock = FakeClock(now ?? DateTime.utc(2026, 10, 7, 12));
    final FakeIdGenerator ids = FakeIdGenerator([
      _invitation,
      '41111111-1111-1111-1111-111111111111',
    ]);
    return InviteToGroup(
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
    );
  }

  RespondToGroupInvitation respond() {
    final FakeClock clock = FakeClock(DateTime.utc(2026, 10, 7, 13));
    return RespondToGroupInvitation(
      invitations: invitations,
      groups: groups,
      join: JoinGroupByInvite(
        repository: groups,
        idGenerator: FakeIdGenerator(['51111111-1111-1111-1111-111111111111']),
        clock: clock,
      ),
      clock: clock,
    );
  }

  setUp(() {
    groups = InMemoryGroupRepository()
      ..seedGroup(storedGroup(id: _group, ownerId: _owner))
      ..seedMembership(
        storedMembership(
          id: '61111111-1111-1111-1111-111111111111',
          groupId: _group,
          userId: _owner,
          role: GroupRole.owner,
        ),
      );
    notifications = InMemoryNotificationRepository();
    invitations = _Invitations();
    sender = _Sender();
  });

  Future<Result<bool>> ownerInvites(String who, {DateTime? now}) =>
      invite(now: now)(
        principal: principalUser(userId: _owner),
        groupId: _group,
        inviteeUserId: who,
      );

  group('InviteToGroup', () {
    test('a member invites: told in the inbox and by push, once', () async {
      expect(await ownerInvites(_friend), const Result<bool>.ok(true));

      expect(invitations.rows.single.status, GroupInvitationStatus.pending);
      final listed = await notifications.listForRecipient(
        const UserId(_friend),
        limit: 10,
      );
      final Notification told = (listed as Ok<List<Notification>>).value.single;
      expect(told.kind, NotificationKind.groupInvited);
      expect(told.subject.groupId, const GroupId(_group));
      expect(sender.titles.single, contains('The Circle'));
      expect(sender.links.single, PushLink.inbox);

      expect(await ownerInvites(_friend), const Result<bool>.ok(false));
      expect(notifications.countFor(_friend), 1);
      expect(sender.titles, hasLength(1));
    });

    test('at night the inbox has it and no phone rings', () async {
      // 23:30 in Riyadh.
      await ownerInvites(_friend, now: DateTime.utc(2026, 10, 7, 20, 30));

      expect(notifications.countFor(_friend), 1);
      expect(sender.titles, isEmpty);
    });

    test('nobody outside the league invites to it', () async {
      final result = await invite()(
        principal: principalUser(userId: _stranger),
        groupId: _group,
        inviteeUserId: _friend,
      );

      expect((result as Err<bool>).error.code, 'group.not_a_member');
      expect(invitations.rows, isEmpty);
    });

    test('nobody invites themselves or a member', () async {
      final self = await ownerInvites(_owner);
      expect((self as Err<bool>).error.code, 'group.invite_self');

      groups.seedMembership(
        storedMembership(
          id: '71111111-1111-1111-1111-111111111111',
          groupId: _group,
          userId: _friend,
        ),
      );
      final member = await ownerInvites(_friend);
      expect((member as Err<bool>).error.code, 'group.already_member');
      expect(invitations.rows, isEmpty);
    });
  });

  group('RespondToGroupInvitation', () {
    test('accepting joins the league', () async {
      await ownerInvites(_friend);

      final result = await respond()(
        principal: principalUser(userId: _friend),
        invitationId: _invitation,
        accept: true,
      );

      expect(
        result,
        const Result<GroupInvitationStatus>.ok(GroupInvitationStatus.accepted),
      );
      final mine = await groups.findMembership(
        const GroupId(_group),
        const UserId(_friend),
      );
      expect((mine as Ok<GroupMembership?>).value, isNotNull);
      expect(invitations.rows.single.status, GroupInvitationStatus.accepted);
    });

    test('declining keeps the player out, and the answer stands', () async {
      await ownerInvites(_friend);

      await respond()(
        principal: principalUser(userId: _friend),
        invitationId: _invitation,
        accept: false,
      );
      final again = await respond()(
        principal: principalUser(userId: _friend),
        invitationId: _invitation,
        accept: true,
      );

      expect(
        again,
        const Result<GroupInvitationStatus>.ok(GroupInvitationStatus.declined),
      );
      final mine = await groups.findMembership(
        const GroupId(_group),
        const UserId(_friend),
      );
      expect((mine as Ok<GroupMembership?>).value, isNull);
    });

    test("someone else's invitation is not found", () async {
      await ownerInvites(_friend);

      final result = await respond()(
        principal: principalUser(userId: _stranger),
        invitationId: _invitation,
        accept: true,
      );

      expect(
        (result as Err<GroupInvitationStatus>).error.code,
        'group.invitation_not_found',
      );
    });
  });

  test('ListMyGroupInvitations answers the caller own only', () async {
    await ownerInvites(_friend);

    final mine = await ListMyGroupInvitations(invitations: invitations)(
      principal: principalUser(userId: _friend),
    );
    final theirs = await ListMyGroupInvitations(invitations: invitations)(
      principal: principalUser(userId: _stranger),
    );

    expect((mine as Ok<List<GroupInvitation>>).value.single.id, _invitation);
    expect((theirs as Ok<List<GroupInvitation>>).value, isEmpty);
  });
}
