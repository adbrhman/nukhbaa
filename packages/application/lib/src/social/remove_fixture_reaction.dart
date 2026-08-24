import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/fixture_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class RemoveFixtureReaction {
  const RemoveFixtureReaction({
    required FixtureReactionRepository reactions,
    required GroupRepository groups,
  }) : _reactions = reactions,
       _groups = groups;

  final FixtureReactionRepository _reactions;
  final GroupRepository _groups;

  Future<Result<bool>> call({
    required AuthenticatedUser principal,
    required String groupId,
    required String fixtureId,
  }) async {
    final auth = Authorization.requireRole(principal, PlatformRole.user);
    if (auth is Err<AuthenticatedUser>) {
      return Result.err(auth.error);
    }

    final gIdResult = GroupId.tryParse(groupId);
    if (gIdResult is Err<GroupId>) {
      return Result.err(gIdResult.error);
    }
    final gId = (gIdResult as Ok<GroupId>).value;

    final fixtureRefResult = FixtureRef.tryParse(fixtureId);
    if (fixtureRefResult is Err<FixtureRef>) {
      return Result.err(fixtureRefResult.error);
    }
    final fixture = (fixtureRefResult as Ok<FixtureRef>).value;

    final membershipResult = await _groups.findMembership(
      gId,
      principal.userId,
    );
    if (membershipResult is Err<GroupMembership?>) {
      return Result.err(membershipResult.error);
    }
    final membership = (membershipResult as Ok<GroupMembership?>).value;
    if (membership == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may remove a reaction in it',
        ),
      );
    }

    return _reactions.removeReaction(gId, fixture, principal.userId);
  }
}
