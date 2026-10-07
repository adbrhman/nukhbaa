import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Where an invitation to a friends' league stands (migration 0097).
enum GroupInvitationStatus {
  /// Waiting for the invited player.
  pending,

  /// The player joined the league.
  accepted,

  /// The player said no.
  declined;

  /// The stored and wire token.
  String get wireValue => name;

  /// The status stored as [raw], or null when it is not one.
  static GroupInvitationStatus? tryParse(String? raw) {
    for (final GroupInvitationStatus status in GroupInvitationStatus.values) {
      if (status.wireValue == raw) return status;
    }
    return null;
  }
}

/// One invitation to a friends' league, as its invited player sees it.
final class GroupInvitation {
  /// Creates the invitation.
  const GroupInvitation({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.inviterUserId,
    required this.inviterName,
    required this.inviteeUserId,
    required this.status,
    required this.createdAt,
  });

  /// The invitation (UUID string).
  final String id;

  /// The league.
  final GroupId groupId;

  /// The league's name.
  final String groupName;

  /// The member who invited.
  final UserId inviterUserId;

  /// Their display name.
  final String inviterName;

  /// The invited player.
  final UserId inviteeUserId;

  /// Where it stands.
  final GroupInvitationStatus status;

  /// When it was sent.
  final DateTime createdAt;
}

/// Where to reach a player's phones, and their clock.
final class GroupInviteePush {
  /// Creates the target.
  const GroupInviteePush({required this.tokens, this.utcOffsetMinutes});

  /// The player's push tokens; empty when none is registered.
  final List<String> tokens;

  /// The player's clock offset, when known.
  final int? utcOffsetMinutes;
}

/// Persistence port for invitations to a friends' league (migration 0097).
///
/// General contract (Application ADR §2): MUST NOT throw -- every outcome
/// is a typed [Result]; MUST map infrastructure failures to
/// [ErrorKind.transient].
abstract interface class GroupInvitationRepository {
  /// Records [id] as [inviter]'s invitation of [invitee] to [groupId],
  /// pending, unless [invitee] was already invited to that league:
  /// `Ok(true)` when recorded, `Ok(false)` when an invitation already
  /// existed (whatever its status).
  Future<Result<bool>> createIfAbsent({
    required String id,
    required GroupId groupId,
    required UserId inviter,
    required UserId invitee,
    required DateTime createdAt,
  });

  /// The invitation [id] when [invitee] is the invited player, else
  /// `Ok(null)`.
  Future<Result<GroupInvitation?>> findForInvitee({
    required String id,
    required UserId invitee,
  });

  /// Moves [invitee]'s pending invitation [id] to [status] at [at]:
  /// `Ok(false)` when it was not pending any more.
  Future<Result<bool>> respond({
    required String id,
    required UserId invitee,
    required GroupInvitationStatus status,
    required DateTime at,
  });

  /// [invitee]'s invitations, newest first, at most [limit].
  Future<Result<List<GroupInvitation>>> listForInvitee(
    UserId invitee, {
    required int limit,
  });

  /// Where to reach [user]'s phones.
  Future<Result<GroupInviteePush>> pushTargetOf(UserId user);
}
