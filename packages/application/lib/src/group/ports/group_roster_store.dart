import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Write and read port for a friends' league's roster beyond joining
/// (audit M-26, L-40): a member leaving or being removed, the owner deleting
/// the league, and which of the members play a month.
///
/// Backed by `PostgresGroupRepository`. Kept apart from [GroupRepository] so
/// the existing fakes of that port stay as they are.
///
/// General contract (Application ADR, Section 2): never throws; an
/// infrastructure failure is [ErrorKind.transient].
abstract interface class GroupRosterStore {
  /// Removes [userId]'s membership of [groupId], with the invitation that
  /// brought them in, so a later invitation can be sent again. `Ok(false)`
  /// when there was no such membership.
  Future<Result<bool>> removeMembership(GroupId groupId, UserId userId);

  /// Deletes [groupId] with everything filed under it (memberships,
  /// invitations, reactions, its notifications). Points are not filed under
  /// a group and are never touched. `Ok(false)` when there was no such
  /// group.
  Future<Result<bool>> deleteGroup(GroupId groupId);

  /// The participant ids, in [seasonId], of the members of [groupId] -- one
  /// read for the whole roster (audit L-40: one read per member before).
  Future<Result<Set<String>>> memberParticipantIds(
    GroupId groupId,
    SeasonId seasonId,
  );

  /// The display names of [groupId]'s members, by user id (batch 141: the
  /// roster shows who is who). A member without a name is absent.
  Future<Result<Map<String, String>>> memberDisplayNames(GroupId groupId);
}
