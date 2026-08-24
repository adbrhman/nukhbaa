import 'package:contracts/contracts.dart';
import 'package:domain/domain.dart';

/// Projects the fixture-scoped Social (Tier-3) read values onto their
/// versioned wire shapes (API ADR §4; docs/project-context.md, Axiom 4
/// Amendment — the per-fixture sibling of `social_dto_mapper.dart`).

/// Projects one domain [FixtureReaction] onto the wire [FixtureReactionDto].
FixtureReactionDto fixtureReactionToDto(FixtureReaction reaction) {
  return FixtureReactionDto(
    id: reaction.id.value,
    groupId: reaction.groupId.value,
    fixtureId: reaction.fixture.value,
    userId: reaction.userId.value,
    emoji: reaction.emoji.wireValue,
    reactedAt: reaction.reactedAt.toUtc().toIso8601String(),
  );
}

/// Shapes the response of `GET /groups/{id}/fixtures/{fixtureId}/reactions` —
/// the fixture's reactions within the group, in the server-defined order
/// (reactedAt ascending). An empty list is a legitimate result.
Map<String, Object?> fixtureReactionsJson(
  String groupId,
  String fixtureId,
  List<FixtureReaction> reactions,
) {
  return FixtureReactionsDto(
    groupId: groupId,
    fixtureId: fixtureId,
    reactions: [for (final r in reactions) fixtureReactionToDto(r)],
  ).toJson();
}
