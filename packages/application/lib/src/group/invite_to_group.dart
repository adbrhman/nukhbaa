import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/group/ports/group_invitation_repository.dart';
import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/notification/create_notification.dart';
import 'package:application/src/notification/ports/push_sender.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: a member of a friends' league invites a player found
/// by name (migration 0097).
///
/// Only a member invites (`group.not_a_member` for anyone else); nobody
/// invites themselves (`group.invite_self`) or a player already in the
/// league (`group.already_member`). A player is invited to a league once:
/// inviting them again answers `Ok(false)` and tells nobody.
///
/// A new invitation tells the player in the inbox and, outside their quiet
/// hours, by push; the inbox is where they accept or decline. Telling is
/// best effort: the invitation stands whether or not a phone was reachable.
///
/// Never throws; returns a typed [Result]: `Ok(true)` when invited now.
final class InviteToGroup {
  /// Creates the use-case over its collaborators.
  const InviteToGroup({
    required GroupRepository groups,
    required GroupInvitationRepository invitations,
    required CreateNotification notify,
    required PushSender sender,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _groups = groups,
       _invitations = invitations,
       _notify = notify,
       _sender = sender,
       _idGenerator = idGenerator,
       _clock = clock;

  final GroupRepository _groups;
  final GroupInvitationRepository _invitations;
  final CreateNotification _notify;
  final PushSender _sender;
  final IdGenerator _idGenerator;
  final Clock _clock;

  /// The push body: who invited is in the inbox row.
  static const String pushBody =
      'صديق يدعوك للمنافسة على ترتيب الشهر. افتح الإشعارات لتقبل أو ترفض.';

  /// The push title for [groupName].
  static String pushTitle(String groupName) => 'دعوة إلى دوري «$groupName»';

  /// [principal] invites [inviteeUserId] to the league [groupId].
  Future<Result<bool>> call({
    required AuthenticatedUser principal,
    required String groupId,
    required String inviteeUserId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);

    final groupResult = GroupId.tryParse(groupId);
    if (groupResult is Err<GroupId>) return Result.err(groupResult.error);
    final GroupId group = (groupResult as Ok<GroupId>).value;
    final inviteeResult = UserId.tryParse(inviteeUserId);
    if (inviteeResult is Err<UserId>) return Result.err(inviteeResult.error);
    final UserId invitee = (inviteeResult as Ok<UserId>).value;

    if (invitee == principal.userId) {
      return const Result.err(
        AppError.invariant('group.invite_self', 'Nobody invites themselves'),
      );
    }

    final mine = await _groups.findMembership(group, principal.userId);
    if (mine is Err<GroupMembership?>) return Result.err(mine.error);
    if ((mine as Ok<GroupMembership?>).value == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the league may invite to it',
        ),
      );
    }
    final theirs = await _groups.findMembership(group, invitee);
    if (theirs is Err<GroupMembership?>) return Result.err(theirs.error);
    if ((theirs as Ok<GroupMembership?>).value != null) {
      return const Result.err(
        AppError.invariant(
          'group.already_member',
          'The player is already in the league',
        ),
      );
    }

    final found = await _groups.findGroup(group);
    if (found is Err<Group?>) return Result.err(found.error);
    final Group? league = (found as Ok<Group?>).value;
    if (league == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the league may invite to it',
        ),
      );
    }

    final DateTime now = _clock.nowUtc();
    final created = await _invitations.createIfAbsent(
      id: _idGenerator.newUuid(),
      groupId: group,
      inviter: principal.userId,
      invitee: invitee,
      createdAt: now,
    );
    if (created is Err<bool>) return Result.err(created.error);
    if (!(created as Ok<bool>).value) return const Result.ok(false);

    await _tell(invitee: invitee, inviter: principal.userId, league: league);
    return const Result.ok(true);
  }

  Future<void> _tell({
    required UserId invitee,
    required UserId inviter,
    required Group league,
  }) async {
    final told = await _notify(
      recipientId: invitee,
      kind: NotificationKind.groupInvited,
      subject: NotificationSubject.groupInvited(
        groupId: league.id,
        actorUserId: inviter,
      ),
    );
    // Already told: a repeat must not ring the phone again.
    if (told is! Ok<bool> || !told.value) return;

    final target = await _invitations.pushTargetOf(invitee);
    if (target is! Ok<GroupInviteePush>) return;
    final GroupInviteePush push = target.value;
    if (push.tokens.isEmpty) return;
    // At night the inbox holds it until the player opens the app.
    if (QuietHours.covers(
      _clock.nowUtc(),
      utcOffsetMinutes: push.utcOffsetMinutes,
    )) {
      return;
    }
    await _sender.send(
      tokens: push.tokens,
      title: pushTitle(league.name),
      body: pushBody,
      link: PushLink.inbox,
    );
  }
}
