import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

/// Query use-case: list every group the caller belongs to — "My Groups"
/// (Application ADR §2: a query intent `ListMyGroups`, separated from
/// commands).
///
/// **Ownership read, not a per-group membership gate** (mirror of
/// [ReadParticipantLedger]'s "only my own ledger" shape, distinct from
/// [GetGroup]/[ListGroupMembers]'s per-group member-only visibility gate):
/// the caller is reading their OWN membership roster, so there is no
/// `group.not_a_member` refusal here — any authenticated platform user may
/// call it, and what varies is only which groups come back (possibly none).
///
/// The principal's own [MyGroupSummary.role] and [MyGroupSummary.joinedAt] on
/// each row come from their own membership, never the body (Security ADR
/// §2) — there is nothing for a caller to spoof here since the id resolved is
/// always their own.
///
/// Never throws; returns a typed [Result]. An empty list is legitimate for a
/// user who belongs to no group.
final class ListMyGroups {
  /// Creates the use-case over its collaborator.
  const ListMyGroups({required GroupRepository repository})
    : _repository = repository;

  final GroupRepository _repository;

  /// Lists the groups [principal] belongs to, most-recently-joined first.
  Future<Result<List<MyGroupSummary>>> call({
    required AuthenticatedUser principal,
  }) async {
    // Layer 1: platform authority — any signed-in user. There is no further
    // gate: every row returned is, by construction, a group this exact
    // principal is already a member of (the repository filters by their own
    // userId), so there is nothing further to authorize per-row.
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    return _repository.listGroupsForUser(principal.userId);
  }
}
