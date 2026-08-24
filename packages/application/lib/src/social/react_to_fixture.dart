import 'package:application/src/common/clock.dart';
import 'package:application/src/common/id_generator.dart';
import 'package:application/src/group/ports/group_repository.dart';
import 'package:application/src/identity/authorization.dart';
import 'package:application/src/social/ports/fixture_reaction_repository.dart';
import 'package:domain/domain.dart';
import 'package:shared/shared.dart';

final class ReactToFixture {
  const ReactToFixture({
    required FixtureReactionRepository reactions,
    required GroupRepository groups,
    required IdGenerator idGenerator,
    required Clock clock,
  }) : _reactions = reactions,
       _groups = groups,
       _idGenerator = idGenerator,
       _clock = clock;

  final FixtureReactionRepository _reactions;
  final GroupRepository _groups;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<Result<FixtureReaction>> call({
    required AuthenticatedUser principal,
    required String groupId,
    required String fixtureId,
    required String emoji,
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

    final emojiResult = ReactionEmoji.tryParse(emoji);
    if (emojiResult is Err<ReactionEmoji>) {
      return Result.err(emojiResult.error);
    }
    final chosen = (emojiResult as Ok<ReactionEmoji>).value;

    final gate = await _requireMember(gId, principal.userId);
    if (gate is Err<void>) {
      return Result.err(gate.error);
    }

    final existingResult = await _reactions.findReaction(
      gId,
      fixture,
      principal.userId,
    );
    if (existingResult is Err<FixtureReaction?>) {
      return Result.err(existingResult.error);
    }
    final existing = (existingResult as Ok<FixtureReaction?>).value;

    final now = _clock.nowUtc();
    final Result<FixtureReaction> built;
    if (existing != null) {
      built = existing.changeEmoji(chosen, now);
    } else {
      final idResult = ReactionId.tryParse(_idGenerator.newUuid());
      if (idResult is Err<ReactionId>) {
        return Result.err(idResult.error);
      }
      built = FixtureReaction.create(
        id: (idResult as Ok<ReactionId>).value,
        groupId: gId,
        fixture: fixture,
        userId: principal.userId,
        emoji: chosen,
        reactedAt: now,
      );
    }
    if (built is Err<FixtureReaction>) {
      return Result.err(built.error);
    }
    final reaction = (built as Ok<FixtureReaction>).value;

    final saved = await _reactions.upsertReaction(reaction);
    return switch (saved) {
      Ok<void>() => Result.ok(reaction),
      Err<void>(:final error) => await _resolveConflict(
        error,
        gId,
        fixture,
        principal.userId,
        chosen,
      ),
    };
  }

  Future<Result<void>> _requireMember(GroupId groupId, UserId userId) async {
    final membershipResult = await _groups.findMembership(groupId, userId);
    if (membershipResult is Err<GroupMembership?>) {
      return Result.err(membershipResult.error);
    }
    final membership = (membershipResult as Ok<GroupMembership?>).value;
    if (membership == null) {
      return const Result.err(
        AppError.authorization(
          'group.not_a_member',
          'Only a member of the group may react in it',
        ),
      );
    }
    return const Result.ok(null);
  }

  Future<Result<FixtureReaction>> _resolveConflict(
    AppError error,
    GroupId groupId,
    FixtureRef fixture,
    UserId userId,
    ReactionEmoji chosen,
  ) async {
    if (error.code != 'social.reaction_conflict') {
      return Result.err(error);
    }
    final reread = await _reactions.findReaction(groupId, fixture, userId);
    if (reread is Err<FixtureReaction?>) {
      return Result.err(reread.error);
    }
    final winning = (reread as Ok<FixtureReaction?>).value;
    if (winning == null) {
      return Result.err(error);
    }
    final updated = winning.changeEmoji(chosen, _clock.nowUtc());
    if (updated is Err<FixtureReaction>) {
      return Result.err(updated.error);
    }
    final reaction = (updated as Ok<FixtureReaction>).value;
    final resaved = await _reactions.upsertReaction(reaction);
    return switch (resaved) {
      Ok<void>() => Result.ok(reaction),
      Err<void>(:final error) => Result.err(error),
    };
  }
}
