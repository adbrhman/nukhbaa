import 'package:domain/src/competition/fixture_ref.dart';
import 'package:domain/src/group/group_id.dart';
import 'package:domain/src/identity/user_id.dart';
import 'package:domain/src/social/reaction_emoji.dart';
import 'package:domain/src/social/reaction_id.dart';
import 'package:shared/shared.dart';

/// A member's emoji reaction to a **fixture**-result within a private group
/// (docs/project-context.md, Axiom 4 Amendment) — the per-fixture sibling of
/// [Reaction].
///
/// [Reaction.roundId] is a required, non-nullable, non-mutable field, so a
/// fixture-scoped reaction cannot be expressed by that type without breaking
/// every existing caller (mirrors why [FixturePointEntry] is a separate
/// aggregate rather than an edit to [PointEntry]). This targets a
/// *fixture*-result by [fixture] instead of a round id; a member has at most
/// one live reaction per fixture-result within a group — uniqueness of
/// `(groupId, fixture, userId)` is enforced structurally in the schema + the
/// use-case, not re-checked here (mirror of [Reaction]).
///
/// Carries no points field (Axiom 5) and no open-graph edge (ADR-001).
/// Pure and immutable; a member swapping their emoji is an idempotent upsert
/// on the unique key (see [changeEmoji]), never a second row.
final class FixtureReaction {
  const FixtureReaction._({
    required this.id,
    required this.groupId,
    required this.fixture,
    required this.userId,
    required this.emoji,
    required this.reactedAt,
  });

  /// Rehydrates a [FixtureReaction] from already-trusted stored fields (used
  /// by the infrastructure mapper). Performs no validation beyond typing —
  /// callers creating a *new* reaction from untrusted input must use
  /// [create].
  const FixtureReaction.fromStored({
    required this.id,
    required this.groupId,
    required this.fixture,
    required this.userId,
    required this.emoji,
    required this.reactedAt,
  });

  /// Creates a new fixture reaction from validated inputs.
  static Result<FixtureReaction> create({
    required ReactionId id,
    required GroupId groupId,
    required FixtureRef fixture,
    required UserId userId,
    required ReactionEmoji emoji,
    required DateTime reactedAt,
  }) {
    if (!reactedAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'social.reaction_reacted_at_not_utc',
          'reactedAt must be provided in UTC',
        ),
      );
    }
    return Result.ok(
      FixtureReaction._(
        id: id,
        groupId: groupId,
        fixture: fixture,
        userId: userId,
        emoji: emoji,
        reactedAt: reactedAt,
      ),
    );
  }

  /// The reaction identity.
  final ReactionId id;

  /// The group this reaction is scoped to (the social container).
  final GroupId groupId;

  /// The fixture-result this reaction targets (by id — Axiom 3).
  final FixtureRef fixture;

  /// The reacting member's platform user id (bound from the verified token
  /// by the use-case, never a request body — Security ADR §2).
  final UserId userId;

  /// The chosen emoji from the closed set.
  final ReactionEmoji emoji;

  /// When the reaction was made or last changed (UTC).
  final DateTime reactedAt;

  /// Returns a copy carrying a new [emoji] and refreshed [reactedAt] (a
  /// member swapping their reaction). The identity + `(groupId, fixture,
  /// userId)` key are unchanged, so persisting this is an idempotent upsert
  /// on the unique key, not a second row. [reactedAt] must be UTC.
  Result<FixtureReaction> changeEmoji(
    ReactionEmoji newEmoji,
    DateTime reactedAt,
  ) {
    if (!reactedAt.isUtc) {
      return const Result.err(
        AppError.validation(
          'social.reaction_reacted_at_not_utc',
          'reactedAt must be provided in UTC',
        ),
      );
    }
    return Result.ok(
      FixtureReaction._(
        id: id,
        groupId: groupId,
        fixture: fixture,
        userId: userId,
        emoji: newEmoji,
        reactedAt: reactedAt,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FixtureReaction &&
      other.id == id &&
      other.groupId == groupId &&
      other.fixture == fixture &&
      other.userId == userId &&
      other.emoji == emoji &&
      other.reactedAt == reactedAt;

  @override
  int get hashCode =>
      Object.hash(id, groupId, fixture, userId, emoji, reactedAt);

  @override
  String toString() =>
      'FixtureReaction(${id.value}, group: ${groupId.value}, '
      'fixture: ${fixture.value}, user: ${userId.value}, '
      '${emoji.wireValue})';
}
