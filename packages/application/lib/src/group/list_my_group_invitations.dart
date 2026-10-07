import 'package:application/src/group/ports/group_invitation_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: the caller's own invitations to friends' leagues
/// (migration 0097), newest first, whatever their status, so the inbox can
/// show who invited, to which league, and the answer given.
final class ListMyGroupInvitations {
  /// Creates the use-case over [invitations].
  const ListMyGroupInvitations({required GroupInvitationRepository invitations})
    : _invitations = invitations;

  final GroupInvitationRepository _invitations;

  /// Most invitations answered.
  static const int limit = 50;

  /// [principal]'s invitations.
  Future<Result<List<GroupInvitation>>> call({
    required AuthenticatedUser principal,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) return Result.err(auth.error);
    return _invitations.listForInvitee(principal.userId, limit: limit);
  }
}
