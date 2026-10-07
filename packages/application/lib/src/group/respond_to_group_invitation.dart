import 'package:application/src/common/clock.dart';
import 'package:application/src/group/join_group_by_invite.dart';
import 'package:application/src/group/ports/group_invitation_repository.dart';
import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Command use-case: the invited player accepts or declines an invitation
/// to a friends' league (migration 0097).
///
/// Only the invited player answers: an unknown invitation, or someone
/// else's, is `group.invitation_not_found` alike. Accepting joins the league
/// exactly as its invite link does ([JoinGroupByInvite], idempotent), then
/// marks the invitation accepted; declining marks it declined and tells
/// nobody. An invitation already answered keeps its answer and returns it.
///
/// Never throws; returns the invitation's status after the answer.
final class RespondToGroupInvitation {
  /// Creates the use-case over its collaborators.
  const RespondToGroupInvitation({
    required GroupInvitationRepository invitations,
    required GroupRepository groups,
    required JoinGroupByInvite join,
    required Clock clock,
  }) : _invitations = invitations,
       _groups = groups,
       _join = join,
       _clock = clock;

  final GroupInvitationRepository _invitations;
  final GroupRepository _groups;
  final JoinGroupByInvite _join;
  final Clock _clock;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  static const AppError _notFound = AppError.invariant(
    'group.invitation_not_found',
    'No such invitation for this player',
  );

  /// [principal] answers invitation [invitationId]: joins when [accept].
  Future<Result<GroupInvitationStatus>> call({
    required AuthenticatedUser principal,
    required String invitationId,
    required bool accept,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    if (!_uuid.hasMatch(invitationId)) {
      return const Result.err(
        AppError.validation(
          'group.invitation_id_invalid',
          'The invitation id is not a UUID',
        ),
      );
    }

    final found = await _invitations.findForInvitee(
      id: invitationId,
      invitee: principal.userId,
    );
    if (found is Err<GroupInvitation?>) return Result.err(found.error);
    final GroupInvitation? invitation = (found as Ok<GroupInvitation?>).value;
    if (invitation == null) return const Result.err(_notFound);
    if (invitation.status != GroupInvitationStatus.pending) {
      return Result.ok(invitation.status);
    }

    if (accept) {
      final league = await _groups.findGroup(invitation.groupId);
      if (league is Err<Group?>) return Result.err(league.error);
      final Group? group = (league as Ok<Group?>).value;
      if (group == null) return const Result.err(_notFound);
      final joined = await _join(
        principal: principal,
        inviteCode: group.inviteCode.value,
      );
      if (joined is Err<GroupMembership>) return Result.err(joined.error);
    }

    final GroupInvitationStatus answer = accept
        ? GroupInvitationStatus.accepted
        : GroupInvitationStatus.declined;
    final marked = await _invitations.respond(
      id: invitationId,
      invitee: principal.userId,
      status: answer,
      at: _clock.nowUtc(),
    );
    if (marked is Err<bool>) return Result.err(marked.error);
    if ((marked as Ok<bool>).value) return Result.ok(answer);
    // Answered meanwhile (a second tap, another device): that answer
    // stands.
    final again = await _invitations.findForInvitee(
      id: invitationId,
      invitee: principal.userId,
    );
    return switch (again) {
      Ok<GroupInvitation?>(:final value) => Result.ok(value?.status ?? answer),
      Err<GroupInvitation?>(:final error) => Result.err(error),
    };
  }
}
